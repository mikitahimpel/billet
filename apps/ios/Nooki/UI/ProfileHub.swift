import SwiftUI

/// What the avatars open: the couple at the top, then their profile, the partner invite while they are two phones
/// apart, and the settings.
struct ProfileHub: View {
    let state: HomeState
    /// Wipes everything saved on this phone and starts the app over.
    var erase: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ServerSession.self) private var session: ServerSession?
    @Environment(Hints.self) private var hints
    @State private var pairing = false

    private var canInvite: Bool {
        guard let session else { return false }
        return !session.isPaired && session.signIn.state == .signedIn
    }

    var body: some View {
        NavigationStack {
            NookiForm {
                couple
                if canInvite {
                    Button(action: invite) { inviteCard }
                        .buttonStyle(PressScaleStyle())
                }
                NookiSection {
                    NavigationLink { ProfileEditor(profile: state.profile) } label: {
                        NookiRowLabel(title: "Edit profile", symbol: "person.2.fill", tint: .sky) { RowChevron() }
                    }
                    if canInvite {
                        Button(action: invite) {
                            NookiRowLabel(title: "Invite your partner", symbol: "heart.circle.fill", tint: .blush) {
                                RowChevron()
                            }
                        }
                    } else if session?.isPaired == true {
                        NookiRowLabel(title: "Paired with your partner", symbol: "heart.fill", tint: .blush)
                    }
                    NavigationLink {
                        SettingsView(state: state) {
                            dismiss()
                            erase()
                        }
                    } label: {
                        NookiRowLabel(title: "Settings", symbol: "gearshape.fill", tint: .lilac) { RowChevron() }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(.honey)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $pairing) {
            if let session {
                PairingSheet(model: session.pairing) { session.pairingFinished() }
                    .presentationBackground(Ink.sheet)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func invite() {
        hints.done(InviteHint())
        pairing = true
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
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Ink.heroInk)
                    .frame(width: 30, height: 30)
                    .background(.honeyGradient, in: .circle)
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                    .offset(y: 8)
            }
            .padding(.bottom, Space.s)
            VStack(spacing: 4) {
                Text("\(state.profile.name(of: state.partners.0)) & \(state.profile.name(of: state.partners.1))")
                    .font(.nookiTitle)
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                Text("Day \(state.daysTogether) together")
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.l)
        .accessibilityElement(children: .combine)
    }

    private var inviteCard: some View {
        HStack(spacing: 14) {
            UsIcon(glyph: .init(symbol: "heart.circle.fill", tint: .blush), size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("Invite your partner")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.heroInk)
                Text("Share \(CatProfile.name()), notes and coins")
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.heroInk.opacity(0.75))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.nookiCaption.weight(.semibold))
                .foregroundStyle(Ink.heroInk.opacity(0.6))
        }
        .padding(Space.l)
        .background(.honeyGradient, in: .rect(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: Color.honeyDeep.opacity(0.35), radius: 10, y: 5)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
