import ActivityKit
import MomentsInterface
import OurioShared
import ProfileInterface
import SwiftUI
import Design
import UsInterface
import Wire
import WidgetKit

/// The partner's new drawing on the lock screen and in the Dynamic Island, until it is dismissed or the system ends
/// it. Tapping opens the composer to draw one back.
struct DrawingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DrawingAttributes.self) { context in
            DrawingActivityBanner(state: context.state, partner: CoupleStore().couple.other)
                .activityBackgroundTint(Ink.surface)
                .activitySystemActionForegroundColor(Ink.text)
                .widgetURL(DeepLink.draw.url)
        } dynamicIsland: { context in
            let partner = CoupleStore().couple.other
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PartnerDot(initial: partner, size: 32)
                }
                DynamicIslandExpandedRegion(.center) {
                    DrawingTile(state: context.state, margin: 0.08)
                        .frame(height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                        .accessibilityLabel("A drawing from \(partner)")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("\(partner) drew you something")
                            .font(.ourioCaption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: Space.s)
                        DrawBackPill()
                    }
                }
            } compactLeading: {
                Image(systemName: "scribble.variable").foregroundStyle(Color.honey)
            } compactTrailing: {
                PartnerDot(initial: partner, size: 20)
            } minimal: {
                Image(systemName: "scribble.variable").foregroundStyle(Color.honey)
            }
            .keylineTint(Color.honey)
            .widgetURL(DeepLink.draw.url)
        }
    }
}

/// Their initial on a honey dot: the one honey mark of the activity, so the island reads as theirs at a glance.
private struct PartnerDot: View {
    let initial: String
    let size: CGFloat

    var body: some View {
        Text(initial.prefix(1))
            .font(.ourioMicro)
            .foregroundStyle(Ink.heroInk)
            .frame(width: size, height: size)
            .background(Color.honey, in: .circle)
            .accessibilityHidden(true)
    }
}

private struct DrawBackPill: View {
    var body: some View {
        Text("Draw back")
            .font(.ourioMicro)
            .foregroundStyle(Ink.heroInk)
            .padding(.horizontal, Space.m)
            .frame(height: Size.pill)
            .background(Color.honey, in: .capsule)
    }
}

/// The lock-screen banner: the drawing as a print on its wallpaper beside who sent it, and the way to answer.
private struct DrawingActivityBanner: View {
    let state: DrawingAttributes.ContentState
    let partner: String

    var body: some View {
        HStack(spacing: Space.l) {
            DrawingTile(state: state, margin: 0.1)
                .frame(width: 132, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                .padding(Space.xs)
                .background(Ink.paper, in: RoundedRectangle(cornerRadius: Radius.inner + Space.xs, style: .continuous))
                .rotationEffect(.degrees(-2))
            VStack(alignment: .leading, spacing: Space.s) {
                Text("\(partner) drew you something")
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.text)
                    .lineLimit(2)
                DrawBackPill()
            }
            Spacer(minLength: 0)
        }
        .padding(Space.l)
        .accessibilityElement(children: .combine)
    }
}

private struct DrawingTile: View {
    let state: DrawingAttributes.ContentState
    let margin: Double

    var body: some View {
        DrawingCard(strokes: state.strokes, wallpaper: LockWallpaper(paper: state.paper), margin: margin)
    }
}
