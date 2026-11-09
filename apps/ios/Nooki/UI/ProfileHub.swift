import SwiftUI
import Design

/// What the avatars open: the couple at the top, then their profile, the partner invite while they are two phones
/// apart, and the settings.
struct ProfileHub: View {
    let state: HomeState
    /// Wipes everything saved on this phone and starts the app over.
    var erase: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ServerSession.self) private var session: ServerSession?
    @State private var pairing = false

    private var canInvite: Bool {
        guard let session else { return false }
        return !session.isPaired && session.signIn.state == .signedIn
    }

    var body: some View {
        BilletSheet("Profile", size: .mediumLarge, scrolls: false) {
            Page {
                couple
                GroupedSection {
                    NavigationLink { ProfileEditor(profile: state.profile) } label: {
                        Row("Edit profile", symbol: "person.2.fill", tint: UsTint.sky.color) { RowChevron() }
                    }
                    if canInvite {
                        Button { pairing = true } label: {
                            Row("Invite your partner", symbol: "heart.circle.fill", tint: UsTint.blush.color) {
                                RowChevron()
                            }
                        }
                    } else if session?.isPaired == true {
                        Row("Paired with your partner", symbol: "heart.fill", tint: UsTint.blush.color)
                    }
                    NavigationLink {
                        SettingsView(state: state) {
                            dismiss()
                            erase()
                        }
                    } label: {
                        Row("Settings", symbol: "gearshape.fill", tint: UsTint.lilac.color) { RowChevron() }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $pairing) {
            if let session {
                PairingSheet(model: session.pairing) { session.pairingFinished() }
            }
        }
    }

    private var couple: some View {
        VStack(spacing: Space.m) {
            HStack(spacing: -14) {
                Monogram(partner: state.partners.0, profile: state.profile, size: 88)
                Monogram(partner: state.partners.1, profile: state.profile, size: 88)
            }
            .overlay(alignment: .bottom) {
                // The honey link between the two.
                Image(systemName: "heart.fill")
                    .font(.ourioMicro)
                    .foregroundStyle(Ink.heroInk)
                    .frame(width: 30, height: 30)
                    .background(.honeyGradient, in: .circle)
                    .overlay(Circle().strokeBorder(Ink.screen, lineWidth: 2))
                    .offset(y: 8)
            }
            .padding(.bottom, Space.s)
            VStack(spacing: 4) {
                Text("\(state.profile.name(of: state.partners.0)) & \(state.profile.name(of: state.partners.1))")
                    .font(.ourioTitle)
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                Text("Day \(state.daysTogether) together")
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.l)
        .accessibilityElement(children: .combine)
    }
}
