import SwiftUI
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
        NavigationStack {
            content
                .scrollContentBackground(.hidden)
                .background(Ink.sheet)
                .navigationTitle("Inbox")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
        .tint(.honey)
        .preferredColorScheme(.dark)
        .task { await model.open() }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unpaired:
            ContentUnavailableView(
                "Nothing here yet", systemImage: "tray",
                description: Text("Once your partner joins, what you both do with \(state.petName) shows up here."))
        case .failed where model.items.isEmpty:
            ContentUnavailableView {
                Label("Couldn't load the Inbox", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try Again") { Task { await model.open() } }
            }
        case .loaded where model.items.isEmpty:
            ContentUnavailableView(
                "All quiet", systemImage: "tray",
                description: Text("Feeding \(state.petName), notes and gifts from you two will show up here."))
                .refreshable { await model.open() }
        case .loaded, .failed:
            list
        }
    }

    private var list: some View {
        List {
            ForEach(InboxDay.group(model.items), id: \.day) { day in
                Section(day.title) {
                    ForEach(day.items, id: \.id) { item in
                        row(item)
                            .onAppear {
                                if item.id == model.items.last?.id { Task { await model.loadMore() } }
                            }
                    }
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await model.open() }
    }

    @ViewBuilder private func row(_ item: ActivityItem) -> some View {
        let rowView = InboxRow(item: item, state: state, isNew: model.fresh.contains(item.id))
        if let target = item.target {
            Button {
                dismiss()
                open(target)
            } label: {
                HStack {
                    rowView
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Ink.secondary.opacity(0.6))
                }
            }
            .buttonStyle(.plain)
        } else {
            rowView
        }
    }
}

/// The Inbox on a phone that isn't connected to the server: nothing can arrive yet, and that is all it says.
struct InboxSignedOut: View {
    let petName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Nothing here yet", systemImage: "tray",
                description: Text("Once you're connected and your partner joins, what you both do with \(petName) "
                                  + "shows up here."))
                .background(Ink.sheet)
                .navigationTitle("Inbox")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
        .tint(.honey)
        .preferredColorScheme(.dark)
    }
}

/// One row: who did it, what, and when.
private struct InboxRow: View {
    let item: ActivityItem
    let state: HomeState
    let isNew: Bool

    var body: some View {
        let line = InboxLine(item, names: names)
        HStack(spacing: 12) {
            avatar
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: line.symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Ink.heroInk)
                        .frame(width: 20, height: 20)
                        .background(Color.honey, in: .circle)
                        .overlay(Circle().stroke(Ink.sheet, lineWidth: 1.5))
                        .offset(x: 4, y: 4)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(line.text)
                    .font(.system(.subheadline, weight: isNew ? .semibold : .medium))
                    .foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(date, format: .relative(presentation: .named))
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(Ink.secondary)
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.14), in: .circle)
        }
    }
}

/// The items of one calendar day, titled "Today", "Yesterday" or the date.
struct InboxDay {
    let day: Date
    let title: String
    let items: [ActivityItem]

    static func group(_ items: [ActivityItem], now: Date = .now, calendar: Calendar = .current) -> [InboxDay] {
        var days: [InboxDay] = []
        for item in items {
            let start = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(item.at) / 1000))
            if let last = days.last, last.day == start {
                days[days.count - 1] = InboxDay(day: start, title: last.title, items: last.items + [item])
            } else {
                days.append(InboxDay(day: start, title: title(start, now: now, calendar: calendar), items: [item]))
            }
        }
        return days
    }

    static func title(_ day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        return day.formatted(sameYear ? .dateTime.weekday(.wide).day().month(.wide) : .dateTime.day().month(.wide).year())
    }
}
