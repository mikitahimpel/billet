import SwiftUI
import TipKit

/// The one header of every top-level screen (World, Moments, Shop): the Inbox and the couple's avatars top-left (the
/// avatars open Us: plans, profile and settings), and the coins top-right. Nothing else sits in it.
struct AppHeader: View {
    let state: HomeState
    @State private var pairing = false
    @Environment(Hints.self) private var hints
    @Environment(ServerSession.self) private var session: ServerSession?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            InboxButton(unread: 0) {}

            Button { state.showsUs = true } label: {
                HStack(spacing: -10) {
                    Monogram(partner: state.partners.0, profile: state.profile)
                        .overlay(alignment: .topLeading) { moodBadge(state.partners.0) }
                    Monogram(partner: state.partners.1, profile: state.profile)
                        .overlay(alignment: .topTrailing) { moodBadge(state.partners.1) }
                }
                .overlay(alignment: .bottom) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.blushPink, in: .circle)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .offset(y: 6)
                }
                .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
                .contentShape(.rect)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Us")
            .accessibilityHint("Your plans, profile and settings")
            .popoverTip(InviteHint(), arrowEdge: .top) { action in
                if action.id == InviteHint.inviteAction {
                    hints.done(InviteHint())
                    pairing = true
                }
            }

            Spacer(minLength: 0)

            CoinPill(coins: state.coins)
        }
        .frame(height: 48)
        .sheet(isPresented: $pairing) {
            if let session {
                PairingSheet(model: session.pairing) { session.pairingFinished() }
                    .presentationBackground(Ink.sheet)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    /// A partner's check-in from the last day, the same one the widgets show.
    @ViewBuilder
    private func moodBadge(_ partner: String) -> some View {
        if let check = state.partnerMoods.latest[partner], check.date > .now.addingTimeInterval(-86_400) {
            Text(check.mood.emoji)
                .font(.system(size: 13))
                .frame(width: 22, height: 22)
                .background(.white, in: .circle)
                .offset(x: partner == state.partners.0 ? -6 : 6, y: -6)
        }
    }
}

/// The Inbox, leftmost in the header: a glass circle with a tray and a count of what is unread.
struct InboxButton: View {
    let unread: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "tray.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Ink.primary)
                .frame(width: 42, height: 42)
                .warmGlass(.circle, interactive: true)
                .overlay(alignment: .topTrailing) {
                    if unread > 0 {
                        Text(unread > 9 ? "9+" : "\(unread)")
                            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Color.blushPink, in: .capsule)
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Inbox")
        .accessibilityValue(unread > 0 ? "\(unread) unread" : "")
    }
}

struct CoinPill: View {
    let coins: Int

    var body: some View {
        HStack(spacing: 8) {
            CoinIcon(size: 24)

            Text("\(coins)")
                .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
        }
        .foregroundStyle(Ink.primary)
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(height: 40)
        .warmGlass(.capsule, interactive: true)
        .animation(.snappy(duration: 0.4), value: coins)
        // Where the coins are on screen, so a purchase can burst coins out of the pill (read it with
        // `.overlayPreferenceValue(CoinPillAnchor.self)`).
        .anchorPreference(key: CoinPillAnchor.self, value: .bounds) { $0 }
    }
}

/// The coin pill's bounds, published by `CoinPill` for effects drawn over the whole screen.
struct CoinPillAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
