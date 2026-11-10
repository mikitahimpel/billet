import BilletKit
import OurioShared
import Foundation

/// What a list screen shows over its rows: one sheet or dialog at a time, never two.
nonisolated enum ListScreenMachine: Machine {
    enum Sheet: Equatable, Sendable {
        case rename
        case confirmingDelete
        case editing(itemID: UUID)
        case addingTitle
        case addingPlace
        case markingBeen(itemID: UUID)
        case openedTitle(itemID: UUID)
    }

    enum State: Equatable, Sendable {
        case browsing
        case showing(Sheet)
    }

    enum Event: Equatable, Sendable {
        case open(Sheet)
        case closed
    }

    enum Output: Equatable, Sendable {}

    static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
        switch (state, event) {
        case (.browsing, .open(let sheet)):
            return (.showing(sheet), [])
        case (.showing, .closed):
            return (.browsing, [])
        // A second sheet waits for the first to close; a stray close changes nothing.
        case (.showing, .open), (.browsing, .closed):
            return (state, [])
        }
    }

    /// The sheet a list opened from the "+" menu starts with, so adding is one tap; a typed list focuses its field.
    static func initial(for kind: ListKind, adding: Bool) -> State {
        guard adding else { return .browsing }
        switch kind {
        case .watch: return .showing(.addingTitle)
        case .travel: return .showing(.addingPlace)
        case .groceries, .food, .books, .bucket, .custom: return .browsing
        }
    }
}
