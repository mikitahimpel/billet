import Foundation
import Wire

/// One list change made on this phone, kept until the pair's room answers it. `apply` does to this phone's copy what
/// the room does to its own, so the change shows at once and again on top of each answer until the room has it.
/// Like the room, it makes nothing twice, so a change the room already holds changes nothing.
nonisolated struct PendingListChange: Codable, Hashable {
    var change: ListCommand
    /// Monogram of the partner who made it; nil when this phone does not know, as from a widget.
    var by: String?
    var at: Date

    func apply(to lists: [UsList]) -> [UsList] {
        var lists = lists
        switch change {
        case .createList(_, let list, let kind, let title, let icon):
            guard let id = UUID(list), !lists.contains(where: { $0.id == id }) else { break }
            lists.append(UsList(id: id, kind: ListKind(kind), title: title, icon: UsGlyph(icon)))
        case .renameList(_, let list, let title, let icon):
            Self.edit(&lists, list) {
                $0.title = title
                $0.icon = UsGlyph(icon)
            }
        case .deleteList(_, let list):
            lists.removeAll { $0.id == UUID(list) }
        case .addItem(_, let list, let item, let text, let details):
            Self.edit(&lists, list) { list in
                guard let id = UUID(item), !list.items.contains(where: { $0.id == id }) else { return }
                var added = ListItem(id: id, text: text, author: by ?? "", added: at)
                added.details = details
                list.items.insert(added, at: 0)
            }
        case .editItem(_, let list, let item, let text, let details):
            Self.edit(&lists, list, item) {
                $0.text = text
                $0.details = details
            }
        case .tickItem(_, let list, let item):
            Self.edit(&lists, list, item) {
                guard $0.done == nil else { return }
                $0.done = at
                $0.doneBy = by
            }
        case .untickItem(_, let list, let item):
            Self.edit(&lists, list, item) {
                $0.done = nil
                $0.doneBy = nil
            }
        case .deleteItem(_, let list, let item):
            Self.edit(&lists, list) { $0.items.removeAll { $0.id == UUID(item) } }
        case .wantItem(_, let list, let item, let wants):
            guard let by else { break }
            Self.edit(&lists, list, item) {
                $0.wants.removeAll { $0 == by }
                if wants { $0.wants.append(by) }
            }
        }
        return lists
    }

    /// The changes that put this phone's own lists in the room: each list the room lacks, its items oldest first,
    /// and their ticks. An empty starter list is left out when the room already has one of its kind.
    static func upload(_ local: [UsList], missingFrom room: [UsList], by me: String) -> [PendingListChange] {
        let held = Set(room.map(\.id))
        let kinds = Set(room.map(\.kind))
        var changes: [PendingListChange] = []
        for list in local where !held.contains(list.id) {
            let starter = list.items.isEmpty && list.kind != .custom && list.title == list.kind.defaultTitle
            if starter && kinds.contains(list.kind) { continue }
            let id = UsStore.key(list.id)
            changes.append(PendingListChange(
                change: .createList(key: .make(), list: id, kind: Wire.ListKind(list.kind),
                                    title: line(list.title, max: 60) ?? list.kind.defaultTitle,
                                    icon: ListIcon(list.icon)),
                by: me, at: .now))
            for item in list.items.reversed() {
                guard let text = line(item.text, max: 300) else { continue }
                let key = UsStore.key(item.id)
                changes.append(PendingListChange(
                    change: .addItem(key: .make(), list: id, item: key, text: text, details: item.details),
                    by: item.author, at: item.added))
                if let done = item.done {
                    changes.append(PendingListChange(change: .tickItem(key: .make(), list: id, item: key),
                                                     by: item.doneBy ?? me, at: done))
                }
            }
        }
        return changes
    }

    /// Trimmed and cut to the room's limit; nil when nothing is left.
    static func line(_ text: String, max: Int) -> String? {
        let text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func edit(_ lists: inout [UsList], _ list: IdempotencyKey, _ body: (inout UsList) -> Void) {
        guard let i = lists.firstIndex(where: { $0.id == UUID(list) }) else { return }
        body(&lists[i])
    }

    private static func edit(_ lists: inout [UsList], _ list: IdempotencyKey, _ item: IdempotencyKey,
                             _ body: (inout ListItem) -> Void) {
        edit(&lists, list) { list in
            guard let i = list.items.firstIndex(where: { $0.id == UUID(item) }) else { return }
            body(&list.items[i])
        }
    }
}

extension UUID {
    nonisolated init?(_ key: IdempotencyKey) { self.init(uuidString: key.rawValue) }
}

extension ListItem {
    /// What the room keeps about the item apart from its text, tick and wants.
    nonisolated var details: ListItemDetails {
        get {
            ListItemDetails(quantity: quantity, note: note, icon: icon, aisle: aisle,
                            media: media.map(ListMedia.init),
                            country: country, place: place ? true : nil, visitedIn: visitedIn,
                            moments: moments.isEmpty ? nil : moments.map(\.uuidString))
        }
        set {
            quantity = newValue.quantity
            note = newValue.note
            icon = newValue.icon
            aisle = newValue.aisle
            media = newValue.media.map(ItemMedia.init)
            country = newValue.country
            place = newValue.place ?? false
            visitedIn = newValue.visitedIn
            moments = newValue.moments?.compactMap(UUID.init(uuidString:)) ?? []
        }
    }
}

extension ItemMedia {
    nonisolated init(_ wire: ListMedia) {
        let kind: Kind = switch wire.kind {
        case .movie: .movie
        case .tv: .tv
        }
        self.init(kind: kind, tmdb: wire.tmdb, year: wire.year, posterPath: wire.posterPath)
    }

    nonisolated var wireKind: ListMediaKind {
        switch kind {
        case .movie: .movie
        case .tv: .tv
        }
    }
}

extension ListMedia {
    nonisolated init(_ media: ItemMedia) {
        self.init(kind: media.wireKind, tmdb: media.tmdb, year: media.year, posterPath: media.posterPath)
    }
}

extension ListKind {
    nonisolated init(_ wire: Wire.ListKind) {
        switch wire {
        case .watch: self = .watch
        case .groceries: self = .groceries
        case .travel: self = .travel
        case .food: self = .food
        case .books: self = .books
        case .bucket: self = .bucket
        case .custom: self = .custom
        }
    }
}

extension Wire.ListKind {
    nonisolated init(_ kind: ListKind) {
        switch kind {
        case .watch: self = .watch
        case .groceries: self = .groceries
        case .travel: self = .travel
        case .food: self = .food
        case .books: self = .books
        case .bucket: self = .bucket
        case .custom: self = .custom
        }
    }
}

extension UsGlyph {
    nonisolated init(_ icon: ListIcon) {
        let tint: UsTint = switch icon.tint {
        case .honey: .honey
        case .blush: .blush
        case .sky: .sky
        case .sage: .sage
        case .lilac: .lilac
        case .sun: .sun
        case .coral: .coral
        }
        self.init(symbol: icon.symbol, tint: tint)
    }
}

extension ListIcon {
    nonisolated init(_ glyph: UsGlyph) {
        let tint: ListTint = switch glyph.tint {
        case .honey: .honey
        case .blush: .blush
        case .sky: .sky
        case .sage: .sage
        case .lilac: .lilac
        case .sun: .sun
        case .coral: .coral
        }
        self.init(symbol: glyph.symbol, tint: tint)
    }
}
