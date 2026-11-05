import FeatureOnboarding
import Pet
import StoreKit
import SwiftUI
import WidgetBridge

/// Settings, pushed from the profile, in clay-card sections: how the app feels, the account, the window, then support,
/// privacy and what's installed. The account is anonymous and needs no sign-in (see `AccountRow`); erasing the data on
/// this phone stands in for account deletion until it has its own row.
struct SettingsView: View {
    let state: HomeState
    /// Wipes everything saved on this phone and starts the app over.
    var erase: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ServerSession.self) private var session: ServerSession?
    @Environment(\.requestReview) private var requestReview
    @AppStorage(AppSettings.hapticsKey) private var haptics = true
    @AppStorage(WindowChoice.key) private var windowView = WindowChoice.suburbia
    @AppStorage(WindowChoice.weatherKey) private var windowWeather = ViewWeather.clear
    @AppStorage(AppSettings.brainCardKey) private var brainCard = false
    @AppStorage(AppSettings.catBrainKey) private var catBrain = true
    @AppStorage(Hints.resetKey) private var hintsReset = false
    @AppStorage(Hints.showAllKey) private var showAllHints = false
    @State private var confirmingErase = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "–") (\(info?["CFBundleVersion"] as? String ?? "–"))"
    }

    var body: some View {
        NookiForm {
            NookiSection(header: "General",
                         footer: hintsReset
                             ? "The hints start over the next time you open Nooki."
                             : "Small taps when you pet \(CatProfile.name()), buy something or add a wish.") {
                NookiToggleRow(title: "Haptics", symbol: "hand.tap.fill", tint: .lilac, isOn: $haptics)
                Button { hintsReset = true } label: {
                    NookiRowLabel(title: "Show hints again", symbol: "lightbulb.fill", tint: .sun) {
                        if hintsReset {
                            Image(systemName: "checkmark")
                                .font(.nookiCallout.weight(.semibold))
                                .foregroundStyle(Ink.accentText)
                        }
                    }
                }
                .buttonStyle(PressScaleStyle())
                .disabled(hintsReset)
            }

            if let session {
                NookiSection(header: "Account") {
                    AccountRow(state: session.signIn.state, retry: session.signIn.retry)
                }
            }

            NookiSection(header: "Window",
                         footer: "What the City room's window looks out on. Suburbia follows the time of day.") {
                NookiPickerRow(title: "View", symbol: "window.horizontal", tint: .sky, selection: $windowView) {
                    ForEach(WindowChoice.allCases) { Text($0.title).tag($0) }
                }
                if windowView == .suburbia {
                    NookiPickerRow(title: "Weather", symbol: "cloud.rain.fill", tint: .sky, selection: $windowWeather) {
                        ForEach(ViewWeather.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }

            NookiSection(header: "Support") {
                Button { requestReview() } label: {
                    NookiRowLabel(title: "Rate Nooki", symbol: "star.fill", tint: .sun) { RowChevron() }
                }
                .buttonStyle(PressScaleStyle())
            }

            NookiSection(header: "Privacy",
                         footer: session == nil
                             ? "Nooki has no account and sends nothing anywhere: your profile, moments, lists and dates "
                               + "are saved only on this phone."
                             : "Your profile, moments, lists and dates are saved only on this phone. Nooki signs in "
                               + "with an anonymous key kept in your iCloud Keychain, without your name or email.") {
                NookiRowLabel(title: "Stays on this iPhone", symbol: "lock.fill", tint: .sage)
                Button(role: .destructive) { confirmingErase = true } label: {
                    NookiRowLabel(title: "Erase All Data", symbol: "trash.fill", tint: .coral, destructive: true)
                }
                .buttonStyle(PressScaleStyle())
            }

            NookiSection(header: "Labs",
                         footer: "With the brain off, \(CatProfile.name()) lives on her own timers as Ilya made her. The "
                             + "card shows what the brain has her doing and why: her state, needs and the last thing she "
                             + "heard. All hints show at once from the next launch, for testing. Rooms shows one room or "
                             + "both on this phone, whatever the test gave your pair.") {
                NookiToggleRow(title: "Cat brain", symbol: "brain", tint: .lilac, isOn: $catBrain)
                NookiToggleRow(title: "Cat brain card", symbol: "brain.head.profile", tint: .lilac, isOn: $brainCard)
                NookiToggleRow(title: "Show all hints now", symbol: "lightbulb.max.fill", tint: .sun,
                               isOn: $showAllHints)
                NavigationLink { StyleGallery() } label: {
                    NookiRowLabel(title: "Style", symbol: "paintpalette.fill", tint: .sun) { RowChevron() }
                }
                .buttonStyle(PressScaleStyle())
                NookiPickerRow(title: "Rooms", symbol: "square.split.2x1", tint: .lilac, selection: roomsOverride) {
                    Text("Follow the test").tag(RoomsVariant?.none)
                    ForEach(RoomsVariant.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
            }

            NookiSection(footer: nil) {
                NookiRowLabel(title: "Version", symbol: "info.circle.fill", tint: .honey) {
                    Text(version)
                        .font(.nookiCallout.monospacedDigit())
                        .foregroundStyle(Ink.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }

            Text("Made with love by Jutsu Studio")
                .font(.nookiCaption)
                .foregroundStyle(Ink.textTertiary)
                .frame(maxWidth: .infinity)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
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

    /// The Labs choice of rooms on this phone; "Follow the test" clears it.
    private var roomsOverride: Binding<RoomsVariant?> {
        Binding(get: { state.rooms.labs }, set: { state.rooms.labs = $0 })
    }
}

/// Where the anonymous sign-in stands, with a retry when the server could not be reached.
private struct AccountRow: View {
    let state: AnonymousSignInMachine.State
    let retry: () -> Void

    var body: some View {
        NookiRowLabel(title: title, detail: detail, symbol: symbol, tint: tint) {
            if case .failed = state {
                Button("Try Again", action: retry)
                    .font(.nookiCallout.weight(.semibold))
                    .foregroundStyle(Ink.accentText)
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
