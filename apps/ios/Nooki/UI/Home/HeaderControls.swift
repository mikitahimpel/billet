import Design
import MomentsInterface
import MoodInterface
import OurioShared
import ProfileInterface
import SwiftUI
import UsInterface

struct InboxButton: View {
    let unread: Int
    var action: () -> Void

    var body: some View {
        GlassIconButton(symbol: "tray.fill", label: "Inbox", badge: unread > 0 ? .count(unread) : .none, action: action)
    }
}

struct MoodHeaderButton: View {
    let state: HomeState
    var action: () -> Void

    private var mine: MoodCheckIn? { state.partnerMoods.latest[state.viewer].flatMap { $0.isFresh() ? $0 : nil } }
    private var theirs: MoodCheckIn? {
        state.partnerMoods.latest[state.otherPartner].flatMap { $0.isFresh() ? $0 : nil }
    }

    var body: some View {
        GlassIconButton(label: "How are you?", action: action) {
            MoodArt(mood: mine?.mood, size: 30)
        }
        .glassControlBadge {
            if let theirs {
                MoodArt(mood: theirs.mood, size: 18)
                    .frame(width: 22, height: 22)
                    .glassBadge(Ink.surface)
                    .offset(x: GlassMetrics.badgeOverhang, y: -GlassMetrics.badgeOverhang)
            }
        }
        .accessibilityValue(value)
        .accessibilityIdentifier("mood")
    }

    private var value: String {
        let partner = state.profile.name(of: state.otherPartner)
        return [
            mine.map { "You feel \($0.mood.title)" },
            theirs.map { "\(partner) feels \($0.mood.title)" },
        ].compactMap(\.self).joined(separator: ", ")
    }
}

/// The coins in a glass capsule as tall as the other header controls. The digits roll only while the number
/// changes; at rest they are plain text, so they stay sharp on the glass.
struct CoinPill: View {
    let coins: Int

    var body: some View {
        HStack(spacing: Space.s) {
            CoinIcon(size: 28)
            Text(coins, format: .number)
                .font(.ourioHeadline.monospacedDigit())
                .contentTransition(.numericText(value: Double(coins)))
                .animation(.snappy(duration: 0.4), value: coins)
        }
        .foregroundStyle(Ink.glassGlyph)
        .padding(.leading, Space.s)
        .padding(.trailing, Space.l - 2)
        .frame(height: Size.control)
        .glass(.capsule, role: .control)
        .contentShape(.capsule)
        // Where the coins are on screen, so a purchase can burst coins out of the pill (read it with
        // `.overlayPreferenceValue(CoinPillAnchor.self)`).
        .anchorPreference(key: CoinPillAnchor.self, value: .bounds) { $0 }
    }
}

struct CoinPillAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Not glass themselves, so the photos stay sharp.
struct CoupleButton: View {
    let state: HomeState
    let plus: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: -Space.m) {
                Monogram(partner: state.partners.0, profile: state.profile, size: Size.control, onGlass: true)
                Monogram(partner: state.partners.1, profile: state.profile, size: Size.control, onGlass: true)
            }
            .overlay(alignment: .bottom) { badge(symbol: "heart.fill").offset(y: 4) }
            .overlay(alignment: .topTrailing) {
                if plus { badge(symbol: "crown.fill").offset(x: 4, y: -4) }
            }
            .frame(height: Size.control)
            .contentShape(.capsule)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Couple")
        .accessibilityHint("Opens your profile")
    }

    private func badge(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.caption2.weight(.bold))
            .frame(width: 20, height: 20)
            .glassBadge()
            .accessibilityHidden(true)
    }
}
