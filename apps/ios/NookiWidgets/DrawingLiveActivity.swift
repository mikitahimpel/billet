import ActivityKit
import SwiftUI
import Design
import Wire
import WidgetKit

/// The partner's new drawing on the lock screen and in the Dynamic Island, until it is dismissed or the system ends
/// it. Tapping opens the composer to draw one back.
struct DrawingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DrawingAttributes.self) { context in
            DrawingActivityBanner(state: context.state, partner: CoupleStore().couple.other)
                .activityBackgroundTint(Color.black.opacity(0.25))
                .widgetURL(DeepLink.draw.url)
        } dynamicIsland: { context in
            let partner = CoupleStore().couple.other
            return DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    DrawingTile(state: context.state, margin: 0.08)
                        .frame(height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(partner) drew on your lock screen")
                        .font(.nookiCaption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            } compactLeading: {
                Image(systemName: "scribble.variable")
                    .foregroundStyle(LockWallpaper(paper: context.state.paper).colors[1])
            } compactTrailing: {
                Text(partner.prefix(1))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            } minimal: {
                Image(systemName: "scribble.variable")
                    .foregroundStyle(LockWallpaper(paper: context.state.paper).colors[1])
            }
            .widgetURL(DeepLink.draw.url)
        }
    }
}

/// The lock-screen banner: the drawing on its wallpaper beside who sent it.
private struct DrawingActivityBanner: View {
    let state: DrawingAttributes.ContentState
    let partner: String

    var body: some View {
        HStack(spacing: 14) {
            DrawingTile(state: state, margin: 0.1)
                .frame(width: 132, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("From \(partner)")
                    .font(.nookiHeadline)
                Text("Tap to draw one back")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

private struct DrawingTile: View {
    let state: DrawingAttributes.ContentState
    let margin: Double

    var body: some View {
        DrawingCard(strokes: state.strokes, wallpaper: LockWallpaper(paper: state.paper), margin: margin)
    }
}
