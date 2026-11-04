import FeatureOnboarding
import StoreKit
import SwiftUI

/// Settings, grouped the way iOS groups its own: the couple first, then how the app feels, then support, privacy and
/// what's installed. The account is anonymous and needs no sign-in (see `AccountRow`); erasing the data on this phone
/// stands in for account deletion until it has its own row.
struct SettingsView: View {
    let state: HomeState
    /// Wipes everything saved on this phone and starts the app over.
    var erase: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AnonymousSignInModel.self) private var signIn: AnonymousSignInModel?
    @Environment(\.requestReview) private var requestReview
    @AppStorage(AppSettings.hapticsKey) private var haptics = true
    @AppStorage(AppSettings.brainCardKey) private var brainCard = false
    @AppStorage(AppSettings.catBrainKey) private var catBrain = true
    @State private var editingProfile = false
    @State private var confirmingErase = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "–") (\(info?["CFBundleVersion"] as? String ?? "–"))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { editingProfile = true } label: { coupleCard }
                }
                .listRowBackground(rowBackground)

                Section {
                    Toggle(isOn: $haptics) { row("Haptics", symbol: "hand.tap.fill", tint: .lilac) }
                } header: {
                    Text("General")
                } footer: {
                    Text("Small taps when you pet Mochi, buy something or add a wish.")
                }
                .listRowBackground(rowBackground)

                if let signIn {
                    Section("Account") {
                        AccountRow(state: signIn.state, retry: signIn.retry)
                    }
                    .listRowBackground(rowBackground)
                }

                Section("Support") {
                    Button { requestReview() } label: { row("Rate Nooki", symbol: "star.fill", tint: .sun) }
                }
                .listRowBackground(rowBackground)

                Section {
                    row("Stays on this iPhone", symbol: "lock.fill", tint: .sage)
                    Button(role: .destructive) { confirmingErase = true } label: {
                        row("Erase All Data", symbol: "trash.fill", tint: .coral, destructive: true)
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text(signIn == nil
                         ? "Nooki has no account and sends nothing anywhere: your profile, moments, lists and dates "
                           + "are saved only on this phone."
                         : "Your profile, moments, lists and dates are saved only on this phone. Nooki signs in "
                           + "with an anonymous key kept in your iCloud Keychain, without your name or email.")
                }
                .listRowBackground(rowBackground)

                Section {
                    Toggle(isOn: $catBrain) { row("Cat brain", symbol: "brain", tint: .lilac) }
                    Toggle(isOn: $brainCard) { row("Cat brain card", symbol: "brain.head.profile", tint: .lilac) }
                } header: {
                    Text("Labs")
                } footer: {
                    Text("With the brain off, Mochi lives on her own timers as Ilya made her. The card shows what the "
                         + "brain has her doing and why: her state, needs and the last thing she heard.")
                }
                .listRowBackground(rowBackground)

                Section {
                    LabeledContent("Version", value: version)
                } footer: {
                    Text("Made with love by Jutsu Studio")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
                .listRowBackground(rowBackground)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Erase all data?", isPresented: $confirmingErase, titleVisibility: .visible) {
                Button("Erase All Data", role: .destructive) {
                    dismiss()
                    erase()
                }
            } message: {
                Text("Your profile, photos, moments, lists, wishes and dates will be deleted from this phone. "
                     + "This can't be undone.")
            }
        }
        .tint(Color(hex: 0xFFC27A))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $editingProfile) {
            ProfileSheet(profile: state.profile)
                .presentationBackground(Ink.sheet)
                .presentationDragIndicator(.visible)
        }
    }

    private let rowBackground = Color.white.opacity(0.06)

    private var coupleCard: some View {
        HStack(spacing: 14) {
            HStack(spacing: -12) {
                Monogram(partner: state.partners.0, profile: state.profile, size: 52)
                Monogram(partner: state.partners.1, profile: state.profile, size: 52)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(state.profile.name(of: state.partners.0)) & \(state.profile.name(of: state.partners.1))")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Day \(state.daysTogether) together · Edit profile")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.vertical, 6)
    }

    private func row(_ title: String, symbol: String, tint: UsTint, destructive: Bool = false) -> some View {
        HStack(spacing: 14) {
            UsIcon(glyph: .init(symbol: symbol, tint: tint), size: 30)
            Text(title)
                .foregroundStyle(destructive ? Color(hex: 0xFF8A7A) : .white)
        }
    }
}

/// Where the anonymous sign-in stands, with a retry when the server could not be reached.
private struct AccountRow: View {
    let state: AnonymousSignInMachine.State
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            UsIcon(glyph: .init(symbol: symbol, tint: tint), size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.white)
                if let detail {
                    Text(detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
            if case .failed = state {
                Button("Try Again", action: retry)
                    .font(.system(size: 15, weight: .semibold))
            } else if case .signingIn = state {
                ProgressView()
            }
        }
    }

    private var title: String {
        switch state {
        case .idle, .signingIn: "Connecting…"
        case .signedIn: "Connected"
        case .failed: "Not connected"
        }
    }

    private var detail: String? {
        switch state {
        case .idle, .signingIn: nil
        case .signedIn: "Anonymous account, no email needed"
        case .failed(let failure, _):
            switch failure {
            case .storage: "This iPhone couldn't save the account"
            case .appleRefused, .rejected, .unavailable, .appleIdInUse: "The server couldn't be reached"
            }
        }
    }

    private var symbol: String {
        switch state {
        case .idle, .signingIn: "icloud"
        case .signedIn: "checkmark.icloud.fill"
        case .failed: "exclamationmark.icloud.fill"
        }
    }

    private var tint: UsTint {
        switch state {
        case .idle, .signingIn: .lilac
        case .signedIn: .sage
        case .failed: .coral
        }
    }
}
