import SwiftUI

/// The one header of every top-level screen (World, Moments, Shop): the couple's avatars top-left, which open Us
/// (plans, profile and settings), and the coins top-right. Nothing else sits in it.
struct AppHeader: View {
    let state: HomeState

    var body: some View {
        HStack(alignment: .center) {
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

            Spacer(minLength: 0)

            CoinPill(coins: state.coins)
        }
        .frame(height: 48)
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
    }
}
