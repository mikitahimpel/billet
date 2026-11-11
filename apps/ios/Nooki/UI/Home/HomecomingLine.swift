import Design
import MomentsInterface
import OurioShared
import Pet
import SwiftUI
import UsInterface

/// The one line Home shows when you come back to the partner's care: the most telling thing they did, and when.
struct HomecomingLine: Equatable {
    let text: String

    /// Most telling first; shooing her off the desk is not news.
    static let order: [LifeEvent.Kind] = [.feed, .play, .pet, .sleep, .note]

    init?(_ care: [LifeEvent], partner: String, cat: String, now: Date = .now, calendar: Calendar = .current,
          locale: Locale = .current) {
        guard let kind = Self.order.first(where: { kind in care.contains { $0.kind == kind } }),
              let last = care.last(where: { $0.kind == kind }),
              let what = Self.deed(kind, partner: partner, cat: cat) else { return nil }
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                                     timeZone: calendar.timeZone)
        let time = last.at.formatted(style)
        if calendar.isDate(last.at, inSameDayAs: now) {
            text = "\(what) at \(time)"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(last.at, inSameDayAs: yesterday) {
            text = "\(what) yesterday at \(time)"
        } else {
            style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide)
            text = "\(what) on \(last.at.formatted(style))"
        }
    }
}

extension HomecomingLine {
    static func deed(_ kind: LifeEvent.Kind, partner: String, cat: String) -> String? {
        switch kind {
        case .feed: "\(partner) fed \(cat)"
        case .play: "\(partner) played with \(cat)"
        case .pet: "\(partner) petted \(cat)"
        case .sleep: "\(partner) put \(cat) to bed"
        case .note: "\(partner) left \(cat) a note"
        case .shoo: nil
        }
    }
}

/// The homecoming line over the room, in the scene's label glass.
struct HomecomingLabel: View {
    let line: HomecomingLine

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "heart.fill")
            Text(line.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.ourioCallout.weight(.semibold))
        .foregroundStyle(Ink.glassGlyph)
        .padding(.horizontal, Space.l)
        .frame(height: 40)
        .glass(.capsule, role: .bar)
        .accessibilityElement(children: .combine)
    }
}
