import SwiftUI

/// Shared calendar: a "Soon" feed of countdowns by default, a month grid as the second view.
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
        VStack(spacing: 0) {
            UsSheetHeader(title: "Calendar", subtitle: "Day \(state.daysTogether) together") {
                UsAddButton { editing = UsEvent(title: "", icon: UsGlyph.palette[0], date: .now) }
            }
            HStack(spacing: 8) {
                UsChip(title: "Soon", selected: !showsMonth) { withAnimation(.snappy(duration: 0.25)) { showsMonth = false } }
                UsChip(title: "Month", selected: showsMonth) { withAnimation(.snappy(duration: 0.25)) { showsMonth = true } }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if showsMonth {
                        let rows = inMonth
                        MonthGrid(month: $month, marked: Set(rows.map { Calendar.current.startOfDay(for: $0.date) }))
                        ForEach(rows) { row($0) }
                    } else {
                        let soon = us.upcoming(togetherSince: state.togetherSince, limit: 60)
                        if soon.isEmpty {
                            UsEmpty(icon: .init(symbol: "calendar", tint: .sky), title: "Nothing coming up", text: "Add a birthday, a trip or anything you're both waiting for.")
                        } else {
                            ForEach(soon) { row($0) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .usSheet()
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
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    Text(item.date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide)))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.secondary)
                }
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Text(item.daysLeft == 0 ? "today" : "\(abs(item.daysLeft))")
                        .font(.system(size: item.daysLeft == 0 ? 14 : 20, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle((0...7).contains(item.daysLeft) ? Color.honey : Ink.primary)
                    if item.daysLeft != 0 {
                        Text((abs(item.daysLeft) == 1 ? "day" : "days") + (item.daysLeft < 0 ? " ago" : ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Ink.secondary)
                    }
                }
            }
            .padding(12)
            .usCard()
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
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Ink.primary)
            .buttonStyle(.plain)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { d in
                    Text(d).font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let isToday = cal.isDateInToday(day)
                        Text("\(cal.component(.day, from: day))")
                            .font(.system(size: 14, weight: isToday ? .bold : .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(isToday ? .white : Ink.primary)
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
        .padding(14)
        .usCard(radius: 24)
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
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New event" : "Edit event")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.primary)
                .padding(.top, 24)

            HStack(spacing: 10) {
                UsIcon(glyph: event.icon, size: 50)
                UsField(placeholder: "Birthday, trip, concert…", text: $event.title)
            }
            UsGlyphPicker(selection: $event.icon)

            DatePicker("Date", selection: $event.date)
                .datePickerStyle(.compact)
                .tint(Color.honey)
                .colorScheme(.dark)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Ink.primary)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .usCard(radius: 16)

            Toggle("Every year", isOn: $event.yearly)
                .tint(Color.honey)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Ink.primary)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .usCard(radius: 16)

            HStack(spacing: 8) {
                UsChip(title: "Ours", selected: event.owner == nil) { event.owner = nil }
                ForEach([state.partners.0, state.partners.1], id: \.self) { p in
                    UsChip(title: p, selected: event.owner == p) { event.owner = p }
                }
            }

            Spacer(minLength: 0)

            UsPrimaryButton(title: "Save") {
                state.us.upsertEvent(event)
                dismiss()
            }
            .opacity(event.title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            .disabled(event.title.trimmingCharacters(in: .whitespaces).isEmpty)

            if !isNew {
                Button("Delete event", role: .destructive) {
                    state.us.deleteEvent(event.id)
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .usSheet()
    }
}
