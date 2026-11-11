import MomentsInterface
import OurioShared
import SwiftUI
import Design
import UsInterface
import WidgetKit

/// Lock Screen: the day counter above the clock, a round countdown and a line from the smart slot.
struct UsAccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.ourio.app.accessory", intent: AccessoryConfiguration.self,
                               provider: OurioProvider<AccessoryConfiguration>()) { entry in
            AccessoryView(entry: entry)
        }
        .configurationDisplayName("Us")
        .description("Days together, the next date and what your partner is up to.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

private struct AccessoryView: View {
    let entry: OurioEntry<AccessoryConfiguration>
    @Environment(\.widgetFamily) private var family

    private var s: OurioSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryInline:
            ViewThatFits {
                if let next = s.next {
                    Text("♥ \(s.daysTogether) days · \(next.title) in \(next.daysLeft)d")
                }
                Text("♥ \(s.daysTogether) days together")
            }
            .containerBackground(for: .widget) {}
            .widgetURL(DeepLink.calendar.url)
        case .accessoryCircular:
            circular
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .widgetURL(DeepLink.calendar.url)
        default:
            rectangular
                .containerBackground(for: .widget) {}
                .widgetURL(line.link.url)
        }
    }

    private var circular: some View {
        VStack(spacing: -1) {
            if entry.configuration.circular == .countdown, let next = s.next {
                Image(systemName: next.icon.symbol).font(.system(size: 10, weight: .semibold))
                Text("\(next.daysLeft)").font(.ourioTitle).minimumScaleFactor(0.6)
                Text(next.daysLeft == 1 ? "day" : "days").font(.ourioMicro)
            } else {
                Image(systemName: "heart.fill").font(.system(size: 10, weight: .semibold))
                Text("\(s.daysTogether)").font(.ourioTitle).minimumScaleFactor(0.6)
                Text("days").font(.ourioMicro)
            }
        }
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(line.title)
                .font(.ourioCallout.weight(.bold))
                .widgetAccentable()
            line.detail
                .font(.ourioCaption)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The smart slot squeezed into two lines of text.
    private var line: (title: String, detail: Text, link: DeepLink) {
        switch s.smartModule {
        case .date:
            if let plan = s.planned {
                return (plan.title, Text("Tonight at \(Text(plan.date, format: .dateTime.hour().minute()))"), .dates)
            }
        case .mood:
            if let check = s.freshPartnerMood {
                return ("\(s.partner) · \(check.mood.title)", Text("\(Text(check.date, style: .relative)) ago"), .room)
            }
        case .list:
            if let list = s.list {
                return ("\(s.partner) added to \(list.title)",
                        Text(list.items.filter { !$0.done }.map(\.text).joined(separator: ", ")), .list(list.id))
            }
        case .us, .mochi, .moment:
            break
        }
        let detail = s.next.map { Text($0.daysLeft == 0 ? "\($0.title) today" : "\($0.title) in \($0.daysLeft)d") }
            ?? Text("together")
        return ("♥ Day \(s.daysTogether)", detail, .calendar)
    }
}
