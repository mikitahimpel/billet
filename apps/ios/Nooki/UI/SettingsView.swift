import FeatureOnboarding
import Pet
import StoreKit
import SwiftUI
import Design
import WidgetBridge

/// Settings, pushed from the profile, in clay-card sections: how the app feels, the account and its delivery health,
/// the partner, the window, then support, privacy and what's installed. The account is anonymous and needs no sign-in
/// (see `AccountRow`). Labs and Testing show only in a debug or TestFlight build.
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
    @AppStorage(BakedShell.labsKey) private var roomShellLabs = ""
    @AppStorage(ComposerStyle.key) private var composerStyle = ComposerStyle.standard
    @State private var confirmingErase = false
    @State private var demoBusy = false
    @State private var demoFailed = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "–") (\(info?["CFBundleVersion"] as? String ?? "–"))"
    }

    var body: some View {
        Page {
            GroupedSection(header: "General",
                         footer: hintsReset
                             ? "The hints start over the next time you open Ourio."
                             : "Small taps when you pet \(CatProfile.name()), buy something or add a wish.") {
                ToggleRow("Haptics", symbol: "hand.tap.fill", tint: UsTint.lilac.color, isOn: $haptics)
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

            if let session {
                GroupedSection(header: "Account") {
                    AccountRow(state: session.signIn.state, retry: session.signIn.retry)
                }
                DeliveryHealthSection()
                PartnerAndAccountSections(session: session, erase: erase)
            } else {
                DeliveryHealthSection()
            }

            GroupedSection(header: "Window",
                         footer: "What the City room's window looks out on. Suburbia follows the time of day.") {
                PickerRow("View", symbol: "window.horizontal", tint: UsTint.sky.color, selection: $windowView) {
                    ForEach(WindowChoice.allCases) { Text($0.title).tag($0) }
                }
                if windowView == .suburbia {
                    PickerRow("Weather", symbol: "cloud.rain.fill", tint: UsTint.sky.color, selection: $windowWeather) {
                        ForEach(ViewWeather.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
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
                    Row("Erase All Data", symbol: "trash.fill", tint: UsTint.coral.color, destructive: true)
                }
                .buttonStyle(PressScaleStyle())
            }

            // Labs and Testing are compiled into Debug, and into Release only with BILLET_LABS=YES (project.yml), so
            // the binary that goes to App Review and the App Store has neither.
            #if DEBUG || LABS_YES
            if let session, let demo = session.demoPartner {
                GroupedSection(header: "Testing", footer: demoFooter(paired: demo, hasPartner: session.isPaired)) {
                    Button { Task { await switchDemoPartner(session, paired: demo) } } label: {
                        Row(demo ? "Remove demo partner" : "Pair with a demo partner",
                                      symbol: "person.2.wave.2.fill", tint: UsTint.blush.color) {
                            if demoBusy { ProgressView() }
                        }
                    }
                    .buttonStyle(PressScaleStyle())
                    .disabled(demoBusy || (!demo && session.isPaired))
                }
            }

            GroupedSection(header: "Labs",
                         footer: "With the brain off, \(CatProfile.name()) lives on her own original timers. The "
                             + "card shows what the brain has her doing and why: her state, needs and the last thing she "
                             + "heard. All hints show at once from the next launch, for testing. Rooms shows one room or "
                             + "both on this phone, whatever the test gave your pair. Room shell builds the walls and floor live or loads "
                             + "them baked, from the next launch. Composer style is how a new note looks.") {
                ToggleRow("Cat brain", symbol: "brain", tint: UsTint.lilac.color, isOn: $catBrain)
                ToggleRow("Cat brain card", symbol: "brain.head.profile", tint: UsTint.lilac.color, isOn: $brainCard)
                ToggleRow("Show all hints now", symbol: "lightbulb.max.fill", tint: UsTint.sun.color,
                               isOn: $showAllHints)
                NavigationLink { StyleGallery() } label: {
                    Row("Style", symbol: "paintpalette.fill", tint: UsTint.sun.color) { RowChevron() }
                }
                .buttonStyle(PressScaleStyle())
                PickerRow("Composer style", symbol: "square.and.pencil", tint: UsTint.sun.color,
                          selection: $composerStyle) {
                    ForEach(ComposerStyle.allCases) { Text($0.title).tag($0) }
                }
                PickerRow("Rooms", symbol: "square.split.2x1", tint: UsTint.lilac.color, selection: roomsOverride) {
                    Text("Follow the test").tag(RoomsVariant?.none)
                    ForEach(RoomsVariant.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                Button {
                    state.showcaseRequested = true
                    state.showsProfile = false
                } label: {
                    Row("Play all animations", symbol: "play.fill", tint: UsTint.sage.color) { RowChevron() }
                }
                .buttonStyle(PressScaleStyle())
                PickerRow("Room shell", symbol: "cube.fill", tint: UsTint.honey.color, selection: roomShellOverride) {
                    Text("Follow the test").tag(RoomShell?.none)
                    Text("Live").tag(Optional(RoomShell.live))
                    Text("Baked").tag(Optional(RoomShell.baked))
                }
            }
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
            Button("Erase All Data", role: .destructive) {
                dismiss()
                erase()
            }
        } message: {
            Text("Your profile, photos, moments, lists, wishes and dates will be deleted from this phone. "
                 + "This can't be undone.")
        }
    }

    private func switchDemoPartner(_ session: ServerSession, paired: Bool) async {
        demoBusy = true
        defer { demoBusy = false }
        do {
            if paired { try await session.removeDemoPartner() } else { try await session.pairWithDemoPartner() }
            demoFailed = false
        } catch {
            demoFailed = true
        }
    }

    private func demoFooter(paired: Bool, hasPartner: Bool) -> String {
        if demoFailed { return "The dev server didn't answer. Try again in a moment." }
        if !paired, hasPartner { return "Only without a partner: this account already has one." }
        return "The dev server plays a partner, so you can try Ourio alone: it answers your notes, reacts to "
            + "your photos, cares for \(CatProfile.name()) and opens the daily gift."
    }

    /// The Labs choice of room shell on this phone; "Follow the test" clears it.
    private var roomShellOverride: Binding<RoomShell?> {
        Binding(
            get: { RoomShell(remoteVariant: roomShellLabs) },
            set: { roomShellLabs = $0?.remoteVariant ?? "" })
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
        Row(title, detail: detail, symbol: symbol, tint: tint.color) {
            if case .failed = state {
                Button("Try Again", action: retry)
                    .font(.ourioCallout.weight(.semibold))
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

/// Where the To watch list's posters, details and streaming services come from, as TMDB's and JustWatch's terms ask,
/// and the Places to go list's flags (MIT, which asks for its notice) and map.
private struct DataCreditsView: View {
    var body: some View {
        Page {
            GroupedSection(header: "TMDB",
                         footer: "This product uses the TMDB API but is not endorsed or certified by TMDB.") {
                Link(destination: URL(string: "https://www.themoviedb.org")!) {
                    Row("The Movie Database", symbol: "film.stack.fill", tint: UsTint.sky.color) { RowChevron() }
                }
            }
            GroupedSection(header: "JustWatch",
                         footer: "Where to watch comes from JustWatch, through TMDB.") {
                Link(destination: URL(string: "https://www.justwatch.com")!) {
                    Row("Streaming data by JustWatch", symbol: "play.tv.fill", tint: UsTint.sun.color) {
                        RowChevron()
                    }
                }
            }
            GroupedSection(header: "Flags",
                         footer: "Round flags from circle-flags by HatScripts, MIT License. Copyright (c) 2026 HatScripts.") {
                Link(destination: URL(string: "https://github.com/HatScripts/circle-flags")!) {
                    Row("circle-flags", symbol: "flag.fill", tint: UsTint.blush.color) { RowChevron() }
                }
            }
            GroupedSection(header: "Map", footer: "The world map is Natural Earth's, in the public domain.") {
                Link(destination: URL(string: "https://www.naturalearthdata.com")!) {
                    Row("Natural Earth", symbol: "globe.europe.africa.fill", tint: UsTint.sage.color) { RowChevron() }
                }
            }
        }
        .navigationTitle("Data and credits")
        .navigationBarTitleDisplayMode(.inline)
    }
}
