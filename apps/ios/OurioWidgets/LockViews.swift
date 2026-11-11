import Design
import MoodInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import WidgetKit

// Lock Screen views: one glyph or two short lines, drawn for the system's vibrant tint, so no colour carries meaning.
// Shared with the app, which draws them live in Settings.

extension EnvironmentValues {
    /// The Settings gallery draws these views outside a widget, where the system gauge has no look of its own.
    @Entry var drawsGaugesItself = false
}

/// A gauge drawn by hand: a ring with a label, or a bar, in the vibrant white of the Lock Screen.
struct DrawnRing<Label: View, Value: View>: View {
    let progress: Double
    let label: Label
    let value: Value

    init(progress: Double, @ViewBuilder label: () -> Label, @ViewBuilder value: () -> Value) {
        self.progress = progress
        self.label = label()
        self.value = value()
    }

    var body: some View {
        ZStack {
            ZStack {
                Circle().trim(from: 0.1, to: 0.9)
                    .stroke(.primary.opacity(0.28), style: StrokeStyle(lineWidth: Space.xs, lineCap: .round))
                Circle().trim(from: 0.1, to: 0.1 + 0.8 * progress)
                    .stroke(.primary, style: StrokeStyle(lineWidth: Space.xs, lineCap: .round))
            }
            .rotationEffect(.degrees(90))
            VStack(spacing: 0) {
                value.font(.ourioHeadline)
                label.font(.ourioMicro)
            }
        }
        .padding(Space.xs)
    }
}

struct DrawnBar: View {
    let progress: Double

    var body: some View {
        Capsule().fill(.primary.opacity(0.28)).frame(height: Space.xs)
            .overlay(alignment: .leading) {
                GeometryReader { geo in Capsule().fill(.primary).frame(width: max(Space.xs, geo.size.width * progress)) }
            }
    }
}

extension View {
    func lockGround() -> some View {
        containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }
}

extension PartnerMood {
    /// A plain glyph for the Lock Screen, where the clay faces would turn into a flat blob.
    var lockSymbol: String {
        switch self {
        case .happy: "face.smiling"
        case .sleepy: "moon.zzz.fill"
        case .missing: "heart.fill"
        case .busy: "book.fill"
        }
    }
}

extension MochiPose {
    var lockSymbol: String {
        switch self {
        case .purring: "heart.fill"
        case .asleep: "moon.zzz.fill"
        case .waiting: "envelope.fill"
        case .chirpy: "music.note"
        case .napping: "zzz"
        case .quiet: "ellipsis.bubble.fill"
        case .idle: "pawprint.fill"
        }
    }
}

// MARK: - Us

struct UsLockView: View {
    let entry: FamilyEntry
    let family: WidgetFamily
    private var s: OurioSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryInline:
            ViewThatFits {
                if let next = s.next {
                    Label("\(s.daysTogether) days · \(next.daysLeft == 0 ? "today" : "\(next.daysLeft)d to go")",
                          systemImage: "heart.fill")
                }
                Label("\(s.daysTogether) days together", systemImage: "heart.fill")
                Label("\(s.daysTogether) days", systemImage: "heart.fill")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Label("Day \(s.daysTogether)", systemImage: "heart.fill")
                    .font(.ourioHeadline)
                    .widgetAccentable()
                if let next = s.next {
                    Text(next.title).font(.ourioCaption).lineLimit(1)
                    Text(next.daysLeft == 0 ? "Today" : "in \(next.daysLeft) \(next.daysLeft == 1 ? "day" : "days")")
                        .font(.ourioCaption).foregroundStyle(.secondary)
                } else {
                    Text("together").font(.ourioCaption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.xs)
        default:
            VStack(spacing: 0) {
                Image(systemName: "heart.fill").font(.ourioMicro)
                Text("\(s.daysTogether)").font(.ourioTitle).monospacedDigit().minimumScaleFactor(0.5).widgetAccentable()
                Text("days").font(.ourioMicro)
            }
        }
    }
}

// MARK: - Streak

struct StreakLockView: View {
    let entry: FamilyEntry
    let family: WidgetFamily
    @Environment(\.drawsGaugesItself) private var drawsGauges
    private var glance: StreakGlance { StreakGlance(entry.facts.streak, on: entry.snapshot.date) }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Streak \(glance.count) · \(glance.caption)", systemImage: "flame.fill")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: Space.xs) {
                Label(glance.count > 0 ? "Streak \(glance.count)" : "No streak", systemImage: "flame.fill")
                    .font(.ourioHeadline)
                    .widgetAccentable()
                Text(glance.caption).font(.ourioCaption).foregroundStyle(.secondary).lineLimit(1)
                if drawsGauges {
                    DrawnBar(progress: glance.progress)
                } else {
                    Gauge(value: glance.progress) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.xs)
        default:
            if drawsGauges {
                DrawnRing(progress: glance.progress) { Image(systemName: "flame.fill") } value: {
                    Text("\(glance.count)").monospacedDigit()
                }
                .widgetAccentable()
            } else {
                Gauge(value: glance.progress) {
                    Image(systemName: "flame.fill")
                } currentValueLabel: {
                    Text("\(glance.count)").monospacedDigit()
                }
                .gaugeStyle(.accessoryCircular)
                .widgetAccentable()
            }
        }
    }
}

// MARK: - Mochi

struct CatLockView: View {
    let entry: FamilyEntry
    let family: WidgetFamily
    private var s: OurioSnapshot { entry.snapshot }
    private var pose: MochiPose { MochiPose.pose(s, drawing: entry.facts.drawing) }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(s.catName) · \(pose.word)", systemImage: pose.lockSymbol)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Label("\(s.catName) · \(pose.word)", systemImage: pose.lockSymbol)
                    .font(.ourioHeadline)
                    .widgetAccentable()
                    .lineLimit(1)
                Text(pose.line(s, drawing: entry.facts.drawing)).font(.ourioCaption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.xs)
        default:
            Image(systemName: pose.lockSymbol)
                .font(.ourioTitle)
                .widgetAccentable()
                .accessibilityLabel("\(s.catName), \(pose.word.lowercased())")
        }
    }
}

// MARK: - Partner

struct PartnerLockView: View {
    let entry: FamilyEntry
    let family: WidgetFamily
    private var s: OurioSnapshot { entry.snapshot }
    private var news: PartnerNews? { PartnerNews.latest(s, drawing: entry.facts.drawing) }

    private var symbol: String {
        switch news {
        case .drawing: "scribble.variable"
        case .mood(let check): check.mood.lockSymbol
        case nil: "ellipsis"
        }
    }

    private var words: String {
        switch news {
        case .drawing: "drew you something"
        case .mood(let check): check.mood.title
        case nil: "Nothing yet"
        }
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(s.partner) · \(words)", systemImage: symbol).privacySensitive()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Label(s.partner, systemImage: symbol).font(.ourioHeadline).widgetAccentable()
                Text(words).font(.ourioCaption).lineLimit(1)
                if let news {
                    Text(news.sentLabel(relativeTo: s.date)).font(.ourioCaption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.xs)
            .privacySensitive()
        default:
            Image(systemName: symbol)
                .font(.ourioTitle)
                .widgetAccentable()
                .privacySensitive()
                .accessibilityLabel("\(s.partner), \(words)")
        }
    }
}
