import SwiftUI
import Design
import FeatureInbox
import Wire

/// The Inbox: what happened in the pair lately, grouped by day, newest first. Opening it marks everything read
/// for this person; rows that were new stay marked until it is opened again. A row with a target opens it.
struct InboxView: View {
    let model: InboxModel
    let state: HomeState
    /// Called with a row's target after the sheet has closed.
    var open: (ActivityTarget) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let layout = InboxLayout(model.sheet)
        BilletSheet("Inbox", size: layout.size, scrolls: layout.scrolls) {
            content
        }
        .task { await model.open() }
    }

    @ViewBuilder private var content: some View {
        switch model.sheet {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.xl)
        case .unpaired:
            EmptyState(
                symbol: "tray", title: "Nothing here yet",
                text: "Once your partner joins, what you both do with \(state.petName) shows up here.")
        case .failed:
            EmptyState(
                symbol: "wifi.exclamationmark", title: "Couldn't load the Inbox",
                text: "Check your connection and try again.") {
                    RetryButton { Task { await model.open() } }
                }
        case .loaded(let page) where page.items.isEmpty:
            VStack(spacing: 0) {
                DeliveryNotice(
                    partner: partnerName, insets: EdgeInsets(top: 0, leading: 0, bottom: Space.l, trailing: 0))
                EmptyState(
                    symbol: "tray", title: "All quiet",
                    text: "Feeding \(state.petName), notes and gifts from you two will show up here.")
            }
        case .loaded(let page), .refreshing(let page), .stale(let page):
            list(page)
        }
    }

    private func list(_ page: InboxMachine.Page) -> some View {
        List {
            ForEach(InboxDay.group(page.items), id: \.day) { day in
                Section(day.title) {
                    ForEach(day.items, id: \.id) { item in
                        row(item, isNew: page.fresh.contains(item.id))
                            .onAppear {
                                if item.id == page.items.last?.id { model.loadMore() }
                            }
                    }
                }
                .listRowBackground(Ink.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await model.open() }
        .safeAreaInset(edge: .top, spacing: 0) {
            DeliveryNotice(
                partner: partnerName, insets: EdgeInsets(top: Space.s, leading: Space.l, bottom: 0, trailing: Space.l))
        }
    }

    private var partnerName: String { state.profile.name(of: state.otherPartner) }

    @ViewBuilder private func row(_ item: ActivityItem, isNew: Bool) -> some View {
        let rowView = InboxRow(item: item, state: state, isNew: isNew)
        if let target = item.target {
            Button {
                dismiss()
                open(target)
            } label: {
                HStack {
                    rowView
                    Image(systemName: "chevron.right")
                        .font(.ourioCaption.weight(.semibold))
                        .foregroundStyle(Ink.textTertiary)
                }
            }
            .buttonStyle(.plain)
        } else {
            rowView
        }
    }
}

/// How tall the Inbox opens: a short state hugs its content like every other short sheet, the list takes the whole
/// sheet and scrolls itself.
enum InboxLayout: Equatable {
    case short
    case list

    init(_ sheet: InboxMachine.Sheet) {
        switch sheet {
        case .loaded(let page), .refreshing(let page), .stale(let page): self = page.items.isEmpty ? .short : .list
        case .idle, .loading, .unpaired, .failed: self = .short
        }
    }

    var size: SheetSize {
        switch self {
        case .short: .fit
        case .list: .large
        }
    }

    /// The list is a `List`, so the sheet must not wrap it in a second scroll view; a fitted sheet measures its
    /// content through that scroll view.
    var scrolls: Bool {
        switch self {
        case .short: true
        case .list: false
        }
    }
}

struct InboxSignedOut: View {
    let petName: String

    var body: some View {
        BilletSheet("Inbox", size: InboxLayout.short.size) {
            EmptyState(
                symbol: "tray", title: "Nothing here yet",
                text: "Once you're connected and your partner joins, what you both do with \(petName) shows up here.")
        }
    }
}

private struct InboxRow: View {
    let item: ActivityItem
    let state: HomeState
    let isNew: Bool

    var body: some View {
        let line = InboxLine(item, names: names)
        HStack(spacing: 12) {
            avatar
                .overlay(alignment: .bottomTrailing) {
                    if let mood = line.mood {
                        MoodArt(mood: mood, size: 24)
                            .offset(x: 5, y: 5)
                    } else {
                        Image(systemName: line.symbol)
                            .font(.ourioMicro)
                            .foregroundStyle(Ink.heroInk)
                            .frame(width: 20, height: 20)
                            .background(Color.honey, in: .circle)
                            .overlay(Circle().stroke(Ink.surface, lineWidth: 1.5))
                            .offset(x: 4, y: 4)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(line.text)
                    .font(.ourioCallout.weight(isNew ? .semibold : .medium))
                    .foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(date, format: .relative(presentation: .named))
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
            Spacer(minLength: 0)
            if isNew {
                Circle()
                    .fill(Color.blushPink)
                    .frame(width: 9, height: 9)
                    .accessibilityLabel("New")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var date: Date { Date(timeIntervalSince1970: TimeInterval(item.at) / 1000) }

    private var names: InboxLine.Names {
        InboxLine.Names(
            partner: state.profile.name(of: state.otherPartner), cat: state.petName,
            title: { Catalog.item($0)?.name })
    }

    @ViewBuilder private var avatar: some View {
        switch item.actor {
        case .me: Monogram(partner: state.viewer, profile: state.profile, size: 40)
        case .partner: Monogram(partner: state.otherPartner, profile: state.profile, size: 40)
        case .cat:
            Group {
                if let image = UIImage(named: "MochiPortrait") {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "cat.fill").foregroundStyle(.white)
                }
            }
            .frame(width: 40, height: 40)
            .background(Color(hex: 0xF2C08A))
            .clipShape(.circle)
            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
        case .store:
            Image(systemName: "applelogo")
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
                .frame(width: 40, height: 40)
                .background(Ink.surfaceRaised, in: .circle)
        }
    }
}
