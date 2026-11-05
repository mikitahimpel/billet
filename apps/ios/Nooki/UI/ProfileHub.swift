import SwiftUI

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
        NavigationStack {
            List {
                Section { couple }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                Section {
                    NavigationLink { ProfileEditor(profile: state.profile) } label: {
                        row("Edit profile", symbol: "person.2.fill", tint: .sky)
                    }
                    if canInvite {
                        Button { pairing = true } label: {
                            row("Invite your partner", symbol: "heart.circle.fill", tint: .blush)
                        }
                    } else if session?.isPaired == true {
                        row("Paired with your partner", symbol: "heart.fill", tint: .blush)
                    }
                    NavigationLink {
                        SettingsView(state: state) {
                            dismiss()
                            erase()
                        }
                    } label: {
                        row("Settings", symbol: "gearshape.fill", tint: .lilac)
                    }
                }
                .nookiRow()
            }
            .scrollContentBackground(.hidden)
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

    private var couple: some View {
        VStack(spacing: Space.m) {
            HStack(spacing: -16) {
                Monogram(partner: state.partners.0, profile: state.profile, size: 84)
                Monogram(partner: state.partners.1, profile: state.profile, size: 84)
            }
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

    private func row(_ title: String, symbol: String, tint: UsTint) -> some View {
        HStack(spacing: 14) {
            UsIcon(glyph: .init(symbol: symbol, tint: tint), size: 30)
            Text(title).foregroundStyle(Ink.text)
        }
    }
}
