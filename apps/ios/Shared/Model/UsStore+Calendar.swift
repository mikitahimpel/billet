import Foundation
import Observation
import Wire

extension UsStore {
    /// Next occurrence of every event, planned date and milestone from `now`'s day on, soonest first.
    func upcoming(togetherSince start: Date, limit: Int = 30, from now: Date = .now) -> [Upcoming] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var rows: [Upcoming] = []

        for e in events {
            var n = 0
            var date = e.date
            if e.yearly {
                while cal.startOfDay(for: date) < today {
                    n += 1
                    date = cal.date(byAdding: .year, value: n, to: e.date) ?? date
                }
            }
            guard cal.startOfDay(for: date) >= today else { continue }
            rows.append(row(e, on: date, id: e.id.uuidString))
        }

        for p in planned where p.rating == nil && cal.startOfDay(for: p.date) >= today {
            rows.append(row(p))
        }

        // Day-count milestones, plus the next month anniversary in the first year and the next yearly one.
        let future = { (row: Upcoming) in row.date >= today }
        let (days, months, years) = milestones(since: start)
        rows += days.filter(future)
        rows += [months.first(where: future), years.first(where: future)].compactMap { $0 }

        return Array(rows.sorted { $0.date < $1.date }.prefix(limit))
    }

    /// Every event, planned date and milestone that falls in `interval`, past ones too; yearly events once per year.
    func occurrences(togetherSince start: Date, in interval: DateInterval) -> [Upcoming] {
        let cal = Calendar.current
        let contains = { (date: Date) in date >= interval.start && date < interval.end }
        var rows: [Upcoming] = []

        for e in events {
            guard e.yearly else {
                if contains(e.date) { rows.append(row(e, on: e.date, id: e.id.uuidString)) }
                continue
            }
            let first = cal.component(.year, from: e.date)
            let years = max(0, cal.component(.year, from: interval.start) - first - 1)...max(0, cal.component(.year, from: interval.end) - first)
            for n in years {
                guard let date = cal.date(byAdding: .year, value: n, to: e.date), contains(date) else { continue }
                rows.append(row(e, on: date, id: "\(e.id.uuidString)-\(n)"))
            }
        }

        rows += planned.filter { contains($0.date) }.map(row)
        let (days, months, years) = milestones(since: start)
        rows += (days + months + years).filter { contains($0.date) }

        return rows.sorted { $0.date < $1.date }
    }

    private func row(_ event: UsEvent, on date: Date, id: String) -> Upcoming {
        Upcoming(id: id, title: event.title, icon: event.icon, date: date, source: .event(event.id))
    }

    private func row(_ plan: PlannedDate) -> Upcoming {
        Upcoming(id: plan.id.uuidString, title: DateIdea.idea(plan.ideaID)?.title ?? "Date",
                 icon: .init(symbol: "heart.text.square.fill", tint: .coral), date: plan.date, source: .date(plan.id))
    }

    /// Day counts, month anniversaries in the first year and yearly anniversaries for ten years, each in date order.
    private func milestones(since start: Date) -> (days: [Upcoming], months: [Upcoming], years: [Upcoming]) {
        let cal = Calendar.current
        let days = [100, 200, 300, 365, 500, 730, 1000, 1500, 2000].compactMap { n in
            cal.date(byAdding: .day, value: n - 1, to: start).map {
                Upcoming(id: "day-\(n)", title: "\(n) days together", icon: .init(symbol: "heart.fill", tint: .blush), date: $0, source: .milestone)
            }
        }
        let months = (1...11).compactMap { m in
            cal.date(byAdding: .month, value: m, to: start).map {
                Upcoming(id: "month-\(m)", title: "\(m) \(m == 1 ? "month" : "months") together", icon: .init(symbol: "sparkles", tint: .sun),
                         date: $0, source: .milestone)
            }
        }
        let years = (1...10).compactMap { y in
            cal.date(byAdding: .year, value: y, to: start).map {
                Upcoming(id: "year-\(y)", title: "\(y) \(y == 1 ? "year" : "years") together", icon: .init(symbol: "crown.fill", tint: .honey),
                         date: $0, source: .milestone)
            }
        }
        return (days, months, years)
    }
}
