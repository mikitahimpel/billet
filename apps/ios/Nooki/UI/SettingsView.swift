import FeatureOnboarding
import MomentsInterface
import WidgetInterface
import WidgetUI
import Pet
import ProfileInterface
import RoomInterface
import StoreKit
import SwiftUI
import Design
import UsInterface
import WidgetBridge

/// The account is anonymous and needs no sign-in (see `AccountRow`). Labs shows only in a debug or Labs build.
struct SettingsView: View {
    let state: HomeState
    var erase: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ServerSession.self) private var session: ServerSession?
    @Environment(\.requestReview) private var requestReview
    @AppStorage(AppSettings.hapticsKey) private var haptics = true
    @AppStorage(AppSettings.streakNudgeKey, store: StreakNudge.settings) private var streakNudge = true
    @AppStorage(Hints.resetKey) private var hintsReset = false
    @State private var confirmingErase = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "–") (\(info?["CFBundleVersion"] as? String ?? "–"))"
    }

    var body: some View {
        Page {
            GroupedSection(header: "General",
                         footer: "Haptics: small taps when you pet \(CatProfile.name()), buy something or add a wish. Pronouns: how Ourio talks about \(CatProfile.name()).") {
                ToggleRow("Haptics", symbol: "hand.tap.fill", tint: UsTint.lilac.color, isOn: $haptics)
                PickerRow("Pronouns", symbol: "pawprint.fill", tint: UsTint.sun.color,
                          selection: Binding(get: { state.pronouns }, set: { state.choosePronouns($0) })) {
                    ForEach(CatPronouns.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }

            GroupedSection(header: "Hints",
                         footer: hintsReset
                             ? "The hints start over the next time you open Ourio."
                             : "Shows the tips again, one at a time, from the next launch.") {
                Button { hintsReset = true } label: {
                    Row("Show hints again", symbol: "lightbulb.fill", tint: UsTint.sun.color) {
                        if hintsReset {
                            Image(systemName: "checkmark")
                                .font(.ourioCallout.weight(.semibold))
                                .foregroundStyle(Ink.accentText)
                        }
                    }
                }
                .buttonStyle(PressScaleStyle())
                .disabled(hintsReset)
            }

            GroupedSection(header: "Widgets",
                           footer: "Mochi, your days together, your partner and more, for the Home Screen and the Lock Screen.") {
                NavigationLink { WidgetsGalleryView() } label: {
                    Row("Widget gallery", symbol: "rectangle.on.rectangle", tint: UsTint.honey.color) { RowChevron() }
                }
                .buttonStyle(PressScaleStyle())
            }

            GroupedSection(header: "Reminders",
                         footer: "One note at 8 pm on a day your love streak would go out at midnight.") {
                ToggleRow("Streak at risk", symbol: "flame.fill", tint: UsTint.coral.color, isOn: $streakNudge)
            }

            if let session {
                GroupedSection(header: "Account") {
                    AccountRow(state: session.signIn.state, retry: session.signIn.retry)
                }
                DeliveryHealthSection()
                PartnerAndAccountSections(session: session, erase: erase)
            } else {
                DeliveryHealthSection()
            }

            GroupedSection(header: "Support") {
                Button { requestReview() } label: {
                    Row("Rate Ourio", symbol: "star.fill", tint: UsTint.sun.color) { RowChevron() }
                }
                .buttonStyle(PressScaleStyle())
            }

            GroupedSection(header: "Privacy",
                         footer: session == nil
                             ? "Ourio has no account and sends nothing anywhere: your profile, moments, lists and dates "
                               + "are saved only on this phone."
                             : "Your profile, moments, lists and dates are saved only on this phone. Ourio signs in "
                               + "with an anonymous key kept in your iCloud Keychain, without your name or email.") {
                Row("Stays on this iPhone", symbol: "lock.fill", tint: UsTint.sage.color)
                Button(role: .destructive) { confirmingErase = true } label: {
                    Row("Erase all data", symbol: "trash.fill", tint: UsTint.coral.color, destructive: true)
                }
                .buttonStyle(PressScaleStyle())
            }

            // Labs is compiled into Debug, and into Release only with BILLET_LABS=YES (project.yml), so the binary that
            // goes to App Review and the App Store does not have it.
            #if DEBUG || LABS_YES
            LabsSections(state: state, session: session)
            #endif

            GroupedSection(footer: nil) {
                NavigationLink { DataCreditsView() } label: {
                    Row("Data and credits", symbol: "film.fill", tint: UsTint.coral.color) { RowChevron() }
                }
                .buttonStyle(PressScaleStyle())
                Row("Version", symbol: "info.circle.fill", tint: UsTint.honey.color) {
                    Text(version)
                        .font(.ourioCallout.monospacedDigit())
                        .foregroundStyle(Ink.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }

            Text("Made with love by Jutsu Studio")
                .font(.ourioCaption)
                .foregroundStyle(Ink.textTertiary)
                .frame(maxWidth: .infinity)
        }
        .task { await session?.checkDemoPartner() }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Erase all data?", isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Erase all data", role: .destructive) {
                dismiss()
                erase()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your profile, photos, moments, lists, wishes and dates will be deleted from this phone. "
                 + "This can't be undone.")
        }
    }
}
