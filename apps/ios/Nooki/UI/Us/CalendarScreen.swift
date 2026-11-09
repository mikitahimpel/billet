import SwiftUI
import Design

struct CalendarScreen: View {
    let state: HomeState

    @State private var showsMonth = false
    @State private var editing: UsEvent?
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now

    private var us: UsStore { state.us }
    private var inMonth: [Upcoming] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else { return [] }
        return us.occurrences(togetherSince: state.togetherSince, in: interval)
    }

    var body: some View {
        BilletSheet("Calendar", scrolls: false) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if showsMonth {
                        let rows = inMonth
                        MonthGrid(month: $month, marked: Set(rows.map { Calendar.current.startOfDay(for: $0.date) }))
                        ForEach(rows) { row($0) }
                    } else {
                        let soon = us.upcoming(togetherSince: state.togetherSince, limit: 60)
                        if soon.isEmpty {
                            EmptyState(icon: .init(symbol: "calendar", tint: .sky), title: "Nothing coming up", text: "Add a birthday, a trip or anything you're both waiting for.")
                        } else {
                            ForEach(soon) { row($0) }
                        }
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.s)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .scrollHeader {
                VStack(spacing: 0) {
                    SheetSubtitle(text: "Day \(state.daysTogether) together")
                    HStack(spacing: Space.s) {
                        FilterChip("Soon", isSelected: !showsMonth) { withAnimation(.snappy(duration: 0.25)) { showsMonth = false } }
                        FilterChip("Month", isSelected: showsMonth) { withAnimation(.snappy(duration: 0.25)) { showsMonth = true } }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s)
            }
        }
        .addToolbarButton { editing = UsEvent(title: "", icon: UsGlyph.palette[0], date: .now) }
        .sheet(item: $editing) { event in
            EventEditor(state: state, event: event, isNew: !us.events.contains { $0.id == event.id })
        }
    }

    private func row(_ item: Upcoming) -> some View {
        Button {
            if case .event(let id) = item.source, let event = us.events.first(where: { $0.id == id }) { editing = event }
        } label: {
            HStack(spacing: 12) {
                UsIcon(glyph: item.icon, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.ourioHeadline)
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                    Text(item.date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide)))
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Text(item.daysLeft == 0 ? "today" : "\(abs(item.daysLeft))")
                        .font((item.daysLeft == 0 ? Font.ourioCaption : Font.ourioTitle).monospacedDigit())
                        .foregroundStyle((0...7).contains(item.daysLeft) ? Color.honey : Ink.text)
                    if item.daysLeft != 0 {
                        Text((abs(item.daysLeft) == 1 ? "day" : "days") + (item.daysLeft < 0 ? " ago" : ""))
                            .font(.ourioMicro)
                            .foregroundStyle(Ink.textSecondary)
                    }
                }
            }
            .padding(CardMetrics.padding)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Month grid

private struct MonthGrid: View {
    @Binding var month: Date
    let marked: Set<Date>

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.ourioHeadline)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
            }
            .font(.ourioHeadline)
            .foregroundStyle(Ink.text)
            .buttonStyle(.plain)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { d in
                    Text(d).font(.ourioMicro).foregroundStyle(Ink.textSecondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let isToday = cal.isDateInToday(day)
                        Text("\(cal.component(.day, from: day))")
                            .font(.ourioCallout.weight(isToday ? .bold : .medium).monospacedDigit())
                            .foregroundStyle(isToday ? Ink.heroInk : Ink.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(isToday ? AnyShapeStyle(.honeyGradient) : AnyShapeStyle(.clear), in: .circle)
                            .overlay(alignment: .bottom) {
                                if marked.contains(day) {
                                    Circle().fill(Color.blushPink).frame(width: 5, height: 5).offset(y: -2)
                                }
                            }
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
        .padding(CardMetrics.padding)
        .cardSurface()
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Leading blanks for the first weekday, then every day of the month at start-of-day.
    private var cells: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let lead = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
        let days = range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: lead) + days
    }

    private func shift(_ months: Int) {
        withAnimation(.snappy(duration: 0.25)) { month = cal.date(byAdding: .month, value: months, to: month) ?? month }
    }
}

// MARK: - Editor

struct EventEditor: View {
    let state: HomeState
    @State var event: UsEvent
    let isNew: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BilletSheet(isNew ? "New event" : "Edit event", onConfirm: save, canConfirm: canSave) {
        VStack(alignment: .leading, spacing: 14) {

            HStack(spacing: 10) {
                UsIcon(glyph: event.icon, size: 50)
                UsField(placeholder: "Birthday, trip, concert…", text: $event.title)
            }
            UsGlyphPicker(selection: $event.icon)

            DatePicker("Date", selection: $event.date)
                .datePickerStyle(.compact)
                .tint(Color.honey)
                .font(.ourioBody)
                .foregroundStyle(Ink.text)
                .fieldSurface()

            Toggle("Every year", isOn: $event.yearly)
                .tint(Color.honey)
                .font(.ourioBody)
                .foregroundStyle(Ink.text)
                .fieldSurface()

            HStack(spacing: 8) {
                FilterChip("Ours", isSelected: event.owner == nil) { event.owner = nil }
                ForEach([state.partners.0, state.partners.1], id: \.self) { p in
                    FilterChip(p, isSelected: event.owner == p) { event.owner = p }
                }
            }

            if !isNew {
                Button("Delete event", role: .destructive) {
                    state.us.deleteEvent(event.id)
                    dismiss()
                }
                .font(.ourioHeadline)
                .frame(maxWidth: .infinity)
            }
        }
        }
    }

    private var canSave: Bool { !event.title.trimmingCharacters(in: .whitespaces).isEmpty }

    private func save() {
        state.us.upsertEvent(event)
        dismiss()
    }
}
