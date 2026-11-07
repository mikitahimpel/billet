import Design
import PetScene
import RealityKit
import Synchronization
import UIKit

/// The header and the tab bar as a perf run shows them: the glass they ship with, the same controls opaque with a
/// shadow, flat with none, or no bars at all. `-perf.hud opaque|flat|hidden` picks one for a whole run; a `cost` run
/// switches from that one to the others.
enum HUDArm: String {
    case glass
    case opaque
    case flat
    case hidden

    static let launch = HUDArm(rawValue: UserDefaults.standard.string(forKey: "perf.hud") ?? "") ?? .glass

    var glass: GlassRendering {
        switch self {
        case .glass, .hidden: .liquid
        case .opaque: .opaque
        case .flat: .flat
        }
    }
}

/// Nooki's side of a `-perf.script` run (`ScenePerf`, read by apps/ios/scripts/perf/measure.sh): the room on screen
/// is the scene a run drives, and the tabs are the ones it switches. Silent without the launch argument.
///
/// A run orbits by turning the room the way a drag does. It has no zoom: the pinch lives inside `DioramaView`.
/// Nooki has one lighting and one cat, so those steps are skipped.
@MainActor
enum NookiPerf {
    /// Starts the frame recorder and the script, and says how to switch tabs. Once, at launch.
    static func start(state: HomeState, hud: @escaping (HUDArm) -> Void,
                      sheetGround: @escaping (SheetGroundStyle) -> Void) {
        guard ScenePerf.isOn else { return }
        setHUD = hud
        seedMoments(state.moments)
        var host = ScenePerf.Host()
        host.lightings = []
        host.cats = []
        host.shotPrefix = "world"
        host.selectTab = { tab in
            switch tab {
            case "shop": state.tab = .shop
            case "notes": state.tab = .moments
            case "us": state.tab = .us
            default: state.tab = .world
            }
        }
        host.scroll = { y in scrolls[state.tab]?(y) }
        // The profile sheet is Settings' way in: today's opaque sheet over the live room, the same with the room
        // paused under it, and a glass one, so the room's cost under a sheet and the glass's come apart.
        host.covers = ["drawing", "inbox", "sheet", "sheet.paused", "sheet.glass"]
        host.setCover = { name in
            state.drawing = name == "drawing"
            state.showsInbox = name == "inbox"
            sheetGround(name == "sheet.glass" ? .glass : .opaque)
            current?.paused = name == "sheet.paused"
            state.showsProfile = name?.hasPrefix("sheet") == true
        }
        ScenePerf.host = host
        ScenePerf.start()
    }

    /// Scrolls each tab's page that a run can scroll (the Shop, the Moments feed), while it is on screen; a run
    /// scrolls the one shown to measure its frames.
    static var scrolls: [HomeTab: (Double) -> Void] = [:]

    private static var setHUD: (HUDArm) -> Void = { _ in }
    /// The room on screen, for the covers and switches that pause it.
    private static weak var current: CatRoom?

    /// Photos a run's Moments feed scrolls through, made once on a phone that has fewer. The first run after an
    /// install (measure.sh's warm-up) pays for them, so every measured run starts with the same feed.
    private static func seedMoments(_ moments: MomentStore) {
        let wanted = 14
        guard moments.moments.count < wanted else { return }
        let size = CGSize(width: 1536, height: 2048)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        for i in moments.moments.count..<wanted {
            let hue = CGFloat(i) / CGFloat(wanted)
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                let colors = [UIColor(hue: hue, saturation: 0.5, brightness: 0.9, alpha: 1).cgColor,
                              UIColor(hue: hue + 0.1, saturation: 0.7, brightness: 0.4, alpha: 1).cgColor]
                let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil)
                guard let gradient else { return }
                let end = CGPoint(x: size.width, y: size.height)
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: end, options: [])
            }
            moments.add(image, caption: "Perf photo \(i + 1)", author: "perf",
                        date: .now.addingTimeInterval(-Double(i) * 3600))
        }
    }

    /// `room` is on screen: the Room (`room on screen`) or the City (`city room on screen`), so a run that waits for
    /// "room on screen" finds either.
    ///
    /// The mark waits for the room's next update, so a room that has to start drawing again (coming back from another
    /// tab) counts the wait for its first live frame.
    static func shown(_ room: CatRoom, kind: RoomKind) {
        guard ScenePerf.isOn else { return }
        ScenePerf.host.shotPrefix = kind == .city ? "city" : "world"
        let start = room.frame
        Task { @MainActor in
            let deadline = ContinuousClock.now + .seconds(5)
            while room.frame == start, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(2)) }
            register(room, kind: kind)
        }
    }

    private static func register(_ room: CatRoom, kind: RoomKind) {
        current = room
        ScenePerf.shown(
            .init(
                name: kind == .city ? "city room" : "room",
                orbit: { deltaX, _ in room.setYaw(room.settledYaw - deltaX * 0.004) },
                zoom: { _ in },
                release: { room.setYaw(0) },
                census: {
                    let skin = SplatSkinner.stats.withLock { $0 }
                    return "kind=\(kind == .city ? "city" : "room") skin_passes=\(skin.passes) skin_skipped=\(skin.skipped)"
                        + " skin_ms=\(String(format: "%.2f", skin.milliseconds))"
                },
                // The arms of the glass-over-the-room comparison, each off against the run's launch arm: "glass hud"
                // off is the opaque header and tab bar, "hud shadow" off the flat one, "hud" off none, and "room
                // paused" off stops the room drawing under them.
                switches: ["cat shadow", "room shadows", "sun shadow", "point lights", "particles", "bloom",
                           "glass hud", "hud shadow", "hud", "room paused"],
                setSwitch: { name, isOn in
                    switch name {
                    case "cat shadow": room.setCatShadow(isOn)
                    case "glass hud": setHUD(isOn ? .launch : .opaque)
                    case "hud shadow": setHUD(isOn ? .launch : .flat)
                    case "hud": setHUD(isOn ? .launch : .hidden)
                    case "room paused": room.paused = !isOn
                    default: RoomSwitches.set(name, isOn, in: room)
                    }
                }
            ))
    }

    /// Mochi stands in a room, posed and ready to draw.
    static func catPlaced() {
        ScenePerf.trace("styled cat placed")
    }

    /// A tab other than the World came on screen, under the names a run waits for.
    static func tabShown(_ tab: HomeTab) {
        guard ScenePerf.isOn else { return }
        switch tab {
        case .shop: ScenePerf.mark("shop on screen")
        case .moments: ScenePerf.mark("notes on screen")
        case .us: ScenePerf.mark("us on screen")
        case .world: break
        }
    }
}

/// A `cost` run's switches that need nothing from the rooms: each finds its part by component under the room's root
/// and takes it away, or puts back what it took. The cat's own shadow stays with `CatRoom.setCatShadow`.
@MainActor
private enum RoomSwitches {
    private static var taken: [String: [(entity: Entity, component: any Component)]] = [:]

    static func set(_ name: String, _ isOn: Bool, in room: CatRoom) {
        if isOn {
            for (entity, component) in taken.removeValue(forKey: name) ?? [] { entity.components.set([component]) }
            return
        }
        guard taken[name] == nil else { return }
        var found: [(Entity, any Component)] = []
        func take<C: Component>(_ type: C.Type, from entity: Entity) {
            guard let component = entity.components[type] else { return }
            found.append((entity, component))
            entity.components.remove(type)
        }
        visit(room.root) { entity in
            switch name {
            case "room shadows":
                if !room.isCat(entity) { take(GroundingShadowComponent.self, from: entity) }
            case "sun shadow":
                take(DirectionalLightComponent.Shadow.self, from: entity)
            case "point lights":
                take(PointLightComponent.self, from: entity)
                take(SpotLightComponent.self, from: entity)
            case "particles":
                take(ParticleEmitterComponent.self, from: entity)
            case "bloom":
                #if compiler(>=6.4)
                if #available(iOS 27, *) { take(BloomComponent.self, from: entity) }
                #endif
            default:
                break
            }
        }
        taken[name] = found
    }

    private static func visit(_ entity: Entity, _ body: (Entity) -> Void) {
        body(entity)
        for child in entity.children { visit(child, body) }
    }
}
