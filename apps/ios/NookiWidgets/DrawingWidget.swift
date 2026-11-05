import SwiftUI
import Wire
import WidgetKit

struct DrawingEntry: TimelineEntry {
    let date: Date
    let drawing: LatestDrawing?
    let partner: String
}

/// Reads the latest drawing from the App Group. The app and the notification extension reload these widgets when
/// they save a new one, so the timeline holds one entry and never refreshes on its own.
struct DrawingProvider: TimelineProvider {
    func placeholder(in context: Context) -> DrawingEntry {
        DrawingEntry(date: .now, drawing: nil, partner: "M")
    }

    func getSnapshot(in context: Context, completion: @escaping (DrawingEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DrawingEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }

    private func entry() -> DrawingEntry {
        DrawingEntry(date: .now, drawing: LatestDrawing.load(), partner: CoupleStore().couple.other)
    }
}

/// The partner's latest drawing, full-bleed on the wallpaper it was drawn on, like their lock screen.
/// On iOS 26 WidgetKit can also wake it with a push.
struct DrawingWidget: Widget {
    var body: some WidgetConfiguration {
        if #available(iOS 26, *) {
            return Self.configuration().pushHandler(DrawingPushHandler.self)
        } else {
            return Self.configuration()
        }
    }

    static func configuration() -> some WidgetConfiguration {
        StaticConfiguration(kind: LatestDrawing.widgetKind, provider: DrawingProvider()) { entry in
            DrawingWidgetView(entry: entry)
                .widgetURL(DeepLink.draw.url)
        }
        .configurationDisplayName("Drawing")
        .description("The latest drawing from your partner. Tap to draw one back.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

private struct DrawingWidgetView: View {
    let entry: DrawingEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var wallpaper: LockWallpaper { LockWallpaper(paper: entry.drawing?.paper) }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if family == .accessoryRectangular {
                    AccessoryWidgetBackground()
                } else {
                    LockWallpaperView(wallpaper: wallpaper)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let drawing = entry.drawing, !drawing.strokes.isEmpty {
            ZStack(alignment: .topLeading) {
                GeometryReader { geometry in
                    InkLayer(strokes: inked(DrawingCard.fitted(drawing.strokes, in: geometry.size,
                                                               margin: family == .accessoryRectangular ? 0.04 : 0.12)))
                        .widgetAccentable()
                }
                if family != .systemSmall && family != .accessoryRectangular {
                    Text("from \(entry.partner) · \(drawing.sentAt, style: .relative)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.15), radius: 3)
                        .padding(12)
                }
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "scribble.variable")
                    .font(.system(size: family == .accessoryRectangular ? 16 : 26, weight: .semibold))
                Text(family == .accessoryRectangular ? "Draw for \(entry.partner)" : "Nothing from \(entry.partner) yet")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                if family != .accessoryRectangular {
                    Text("Tap to draw on their lock screen")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .opacity(0.8)
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(family == .accessoryRectangular ? Color.primary : .white)
            .padding(10)
        }
    }

    /// On tinted and lock-screen renderings the system colours the widget itself, so the ink is drawn plain white.
    private func inked(_ strokes: [Stroke]) -> [Stroke] {
        guard renderingMode != .fullColor else { return strokes }
        return strokes.map { Stroke(color: "#FFFFFF", width: $0.width, points: $0.points) }
    }
}

/// Keeps the widgets' APNs push token in the App Group; the app registers it with the server on its next launch,
/// as the extension has no session of its own.
@available(iOS 26, *)
struct DrawingPushHandler: WidgetPushHandler {
    func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
        let token = pushInfo.token.map { String(format: "%02x", $0) }.joined()
        PushTokens.save(widget: token)
    }
}
