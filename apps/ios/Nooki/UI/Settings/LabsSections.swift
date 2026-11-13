#if DEBUG || LABS_YES
import Design
import MomentsInterface
import Pet
import ProfileInterface
import RoomInterface
import SwiftUI
import UsInterface
import WidgetInterface
import WidgetUI

/// Settings → Labs: tools and switches for the people building Ourio, in groups. A Release build has none of it.
struct LabsSections: View {
    let state: HomeState
    let session: ServerSession?

    @AppStorage(AppSettings.brainCardKey) private var brainCard = false
    @AppStorage(AppSettings.catBrainKey) private var catBrain = true
    @AppStorage(AppSettings.quietRoomKey) private var quietRoom = QuietChrome.dim
    @AppStorage(Hints.showAllKey) private var showAllHints = false
    @AppStorage(BakedShell.labsKey) private var roomShellLabs = ""
    @AppStorage(ComposerStyle.key) private var composerStyle = ComposerStyle.standard
    @AppStorage(Look.key) private var look = Look.classic
    @AppStorage(WindowChoice.key) private var windowView = WindowChoice.defaultChoice
    @AppStorage(WindowChoice.weatherKey) private var windowWeather = ViewWeather.clear
    @Environment(PerfLab.self) private var perfLab: PerfLab?
    @State private var demoBusy = false
    @State private var demoFailed = false

    var body: some View {
        GroupedSection(header: "Labs · Look",
                       footer: "Look is the app's colours and faces, from the next launch. Composer style is how a new note "
                           + "looks. Quiet room dims or hides the controls over the room after a few seconds without a touch. "
                           + "Style is the gallery of every colour, font and component.") {
            PickerRow("Look", symbol: "moon.stars.fill", tint: UsTint.honey.color, selection: $look) {
                ForEach(Look.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            PickerRow("Composer style", symbol: "square.and.pencil", tint: UsTint.sun.color,
                      selection: $composerStyle) {
                ForEach(ComposerStyle.allCases) { Text($0.title).tag($0) }
            }
            PickerRow("Quiet room", symbol: "moon.zzz.fill", tint: UsTint.lilac.color, selection: $quietRoom) {
                ForEach(QuietChrome.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            NavigationLink { StyleGallery() } label: {
                Row("Style", symbol: "paintpalette.fill", tint: UsTint.sun.color) { RowChevron() }
            }
            .buttonStyle(PressScaleStyle())
        }

        GroupedSection(header: "Labs · Window view",
                       footer: "What the bedroom's window looks out on. Suburbia follows the time of day. A release build "
                           + "always shows Suburbia in clear weather.") {
            PickerRow("View", symbol: "window.horizontal", tint: UsTint.sky.color, selection: $windowView) {
                ForEach(WindowChoice.allCases) { Text($0.title).tag($0) }
            }
            if windowView == .suburbia {
                PickerRow("Weather", symbol: "cloud.rain.fill", tint: UsTint.sky.color, selection: $windowWeather) {
                    ForEach(ViewWeather.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        }

        GroupedSection(header: "Labs · Rooms",
                       footer: "Rooms shows the living room, the bedroom or both on this phone, whatever the test gave your "
                           + "pair. Room shell builds the walls and floor live or loads them baked, from the next launch.") {
            PickerRow("Rooms", symbol: "square.split.2x1", tint: UsTint.lilac.color, selection: roomsOverride) {
                Text("Follow the test").tag(RoomsVariant?.none)
                ForEach(RoomsVariant.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }
            PickerRow("Room shell", symbol: "cube.fill", tint: UsTint.honey.color, selection: roomShellOverride) {
                Text("Follow the test").tag(RoomShell?.none)
                Text("Live").tag(Optional(RoomShell.live))
                Text("Baked").tag(Optional(RoomShell.baked))
            }
            Button {
                state.showcaseRequested = true
                state.showsProfile = false
            } label: {
                Row("Play all animations", symbol: "play.fill", tint: UsTint.sage.color) { RowChevron() }
            }
            .buttonStyle(PressScaleStyle())
        }

        GroupedSection(header: "Labs · Cat",
                       footer: state.pronouns.say(.brainFooter(name: CatProfile.name()))) {
            ToggleRow("Cat brain", symbol: "brain", tint: UsTint.lilac.color, isOn: $catBrain)
            ToggleRow("Cat brain card", symbol: "brain.head.profile", tint: UsTint.lilac.color, isOn: $brainCard)
        }

        if let perfLab {
            GroupedSection(header: "Labs · Performance",
                           footer: "Switches suspects off while the app runs, forces a quality tier and reads out the frame "
                               + "meter and the room stats.") {
                NavigationLink { PerfLabPage(lab: perfLab) } label: {
                    Row("Performance", symbol: "speedometer", tint: UsTint.sage.color) { RowChevron() }
                }
                .buttonStyle(PressScaleStyle())
            }
        }

        GroupedSection(header: "Labs · Test tools",
                       footer: testToolsFooter) {
            ToggleRow("Show all hints now", symbol: "lightbulb.max.fill", tint: UsTint.sun.color,
                      isOn: $showAllHints)
            if let session {
                LabsCoinsRows(shop: state.shop, purchases: session.purchases)
                if let demo = session.demoPartner {
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
        }
    }

    private var testToolsFooter: String {
        var text = "All hints show at once from the next launch. Coins come from the dev server's mock store, into the "
            + "pair's wallet."
        if let session, let demo = session.demoPartner { text += " " + demoFooter(paired: demo, hasPartner: session.isPaired) }
        return text
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
        if !paired, hasPartner { return "The demo partner needs an account without a partner." }
        return "The demo partner plays your partner, so you can try Ourio alone."
    }

    private var roomShellOverride: Binding<RoomShell?> {
        Binding(
            get: { RoomShell(remoteVariant: roomShellLabs) },
            set: { roomShellLabs = $0?.remoteVariant ?? "" })
    }

    private var roomsOverride: Binding<RoomsVariant?> {
        Binding(get: { state.rooms.labs }, set: { state.rooms.labs = $0 })
    }
}
#endif
