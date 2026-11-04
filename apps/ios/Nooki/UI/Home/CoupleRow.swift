import SwiftUI

struct CoupleRow: View {
    let state: HomeState
    @State private var editing = false

    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 12) {
                Menu {
                    Section("How are you, \(state.profile.name(of: state.viewer))?") {
                        ForEach(PartnerMood.allCases, id: \.self) { mood in
                            Button("\(mood.emoji) \(mood.title.capitalized)") { state.setMood(mood) }
                        }
                    }
                    Button("Edit profile", systemImage: "person.crop.circle") { editing = true }
                    Button("Settings", systemImage: "gearshape") { state.showsSettings = true }
                } label: {
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
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Day \(state.daysTogether)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Ink.primary)
                    Text("together")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.secondary)
                }
                // The clear glass lets the light cushions through; a soft shadow keeps the lines legible over them.
                .shadow(color: .black.opacity(0.25), radius: 2)
            }
            .padding(.leading, 5)
            .padding(.trailing, 18)
            .padding(.vertical, 5)
            .warmGlass(.capsule)

            Spacer(minLength: 0)

            CoinPill(coins: state.coins)
        }
        .sheet(isPresented: $editing) {
            ProfileSheet(profile: state.profile)
                .presentationBackground(Ink.sheet)
                .presentationDragIndicator(.visible)
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
