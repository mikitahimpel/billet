import Design
import PetScene
import RealityKit
import Synchronization
import UIKit

/// Header and tab bar: shipped glass, opaque with a shadow, flat, or none. `-perf.hud opaque|flat|hidden` picks one
/// for a whole run; a `cost` run switches from it to the others.
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

/// Ourio's side of a `-perf.script` run (`ScenePerf`, read by apps/ios/scripts/perf/measure.sh). Silent without the
/// launch argument. Orbits turn the room as a drag does; no zoom, since the pinch lives inside `DioramaView`.
@MainActor
enum OurioPerf {
    /// Once, at launch.
    static func start(state: HomeState, hud: @escaping (HUDArm) -> Void,
                      sheetGround: @escaping (SheetGroundStyle) -> Void, selectRoom: @escaping (RoomKind) -> Void) {
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
        if state.rooms.variant.hasRoomChoice {
            let kinds = state.rooms.variant.kinds
            host.rooms = { (kinds.filter { $0 == state.room } + kinds.filter { $0 != state.room }).map(\.perfName) }
            host.selectRoom = { name in
                if let kind = kinds.first(where: { $0.perfName == name }) { selectRoom(kind) }
            }
        }
        // Opaque sheet over the live room, over the paused room, and a glass one, so the room's cost and the glass's
        // come apart.
        host.covers = ["sheet", "sheet.paused", "sheet.glass", "drawing", "inbox"]
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

    /// A run scrolls the shown tab's page to measure its frames.
    static var scrolls: [HomeTab: (Double) -> Void] = [:]

    private static var setHUD: (HUDArm) -> Void = { _ in }
    /// For the covers and switches that pause it.
    private static weak var current: CatRoom?

    /// Made once on a phone with fewer; measure.sh's warm-up run pays for it, so every measured run has the same feed.
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

    /// Marks "room on screen" for the Room and the City alike. Waits for the room's next update, so a room that must
    /// start drawing again counts the wait for its first live frame.
    static func shown(_ room: CatRoom, kind: RoomKind) {
        guard ScenePerf.isOn else { return }
        ScenePerf.host.shotPrefix = kind == .city ? "city" : "world"
        let start = room.frame
        Task { @MainActor in
            if kind == .home { await PerfPieces.stand(in: room) }
            let deadline = ContinuousClock.now + .seconds(5)
            while room.frame == start, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(2)) }
            register(room, kind: kind)
        }
    }

    private static func register(_ room: CatRoom, kind: RoomKind) {
        current = room
        ScenePerf.shown(
            .init(
                name: kind.perfName,
                orbit: { deltaX, _ in room.setYaw(room.settledYaw - deltaX * 0.004) },
                zoom: { _ in },
                release: { room.setYaw(0) },
                census: {
                    let skin = SplatSkinner.stats.withLock { $0 }
                    return "kind=\(kind == .city ? "city" : "room") skin_passes=\(skin.passes) skin_skipped=\(skin.skipped)"
                        + " skin_ms=\(String(format: "%.2f", skin.milliseconds)) pieces=\(PerfPieces.arm ?? "none")"
                },
                // Each off against the launch arm: "glass hud" off = opaque bars, "hud shadow" off = flat, "hud" off
                // = none, "room paused" stops the room under them; "pieces" removes a `-perf.pieces` run's shop pieces.
                switches: ["cat shadow", "room shadows", "sun shadow", "point lights", "particles", "bloom",
                           "glass hud", "hud shadow", "hud", "room paused", "pieces"],
                setSwitch: { name, isOn in
                    switch name {
                    case "cat shadow": room.setCatShadow(isOn)
                    case "pieces": PerfPieces.set(isOn, in: room)
                    case "glass hud": setHUD(isOn ? .launch : .opaque)
                    case "hud shadow": setHUD(isOn ? .launch : .flat)
                    case "hud": setHUD(isOn ? .launch : .hidden)
                    case "room paused": room.paused = !isOn
                    default: RoomSwitches.set(name, isOn, in: room)
                    }
                }
            ))
    }

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

/// `cost` run switches needing nothing from the rooms: each finds its part by component under the root and
/// removes or restores it. The cat's own shadow stays with `CatRoom.setCatShadow`.
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

/// `-perf.pieces today|sand3d`: three shop pieces on the Room's floor, so a `cost` run's "pieces" switch measures
/// furniture's draw cost. Scaled as the shop fits them, lit like `DioramaScene`'s furniture. The app never
/// places shop pieces otherwise.
@MainActor
enum PerfPieces {
    static let arm = UserDefaults.standard.string(forKey: "perf.pieces")

    private enum Measure { case width, height }

    private struct Piece {
        let model: String
        let measure: Measure
        /// Room units, as `ShopItem.Fit` sizes.
        let size: Float
        /// On the pivot's floor, which is 0.014 above its origin.
        let at: SIMD3<Float>
        let yaw: Float
    }

    private static let floor: Float = 0.014
    private static let spots: [(SIMD3<Float>, Float)] = [
        ([-0.27, floor, 0.12], .pi / 2), ([0.12, floor, -0.39], 0), ([-0.39, floor, -0.39], 0.6),
    ]

    private static func pieces(_ arm: String) -> [Piece]? {
        let models: [(String, Measure, Float)]
        switch arm {
        case "today": models = [("Item_armchair", .width, 0.4), ("Item_bookcase", .height, 0.6),
                                ("Item_monstera", .height, 0.55)]
        case "sand3d": models = [("Item_armchair-meadow", .width, 0.4), ("Item_chest", .height, 0.34),
                                 ("Item_monstera-potted", .height, 0.55)]
        default: return nil
        }
        return zip(models, spots).map { model, spot in
            Piece(model: model.0, measure: model.1, size: model.2, at: spot.0, yaw: spot.1)
        }
    }

    private static var stood: [ObjectIdentifier: Entity] = [:]

    static func stand(in room: CatRoom) async {
        guard let arm, let pieces = pieces(arm), stood[ObjectIdentifier(room)] == nil else { return }
        let group = Entity()
        group.name = "perf pieces"
        stood[ObjectIdentifier(room)] = group
        for piece in pieces {
            let model: Entity
            do {
                model = try await Entity(named: piece.model, in: .main)
            } catch {
                ScenePerf.trace("pieces: \(piece.model) failed to load: \(error)")
                continue
            }
            let bounds = model.visualBounds(relativeTo: nil)
            let extent = piece.measure == .width ? bounds.extents.x : bounds.extents.y
            guard extent > 0 else { continue }
            let scale = piece.size / extent
            let holder = Entity()
            holder.addChild(model)
            model.scale = .init(repeating: scale)
            model.position = [-bounds.center.x * scale, -bounds.min.y * scale, -bounds.center.z * scale]
            holder.position = piece.at
            holder.orientation = simd_quatf(angle: piece.yaw, axis: [0, 1, 0])
            model.forEachDescendant { entity in
                if let receiver = room.iblReceiver { entity.components.set(receiver) }
                entity.components.set(GroundingShadowComponent(castsShadow: true))
            }
            group.addChild(holder)
        }
        room.pivot.addChild(group)
        ScenePerf.trace("pieces \(arm) stood: \(group.children.count)")
    }

    static func set(_ isOn: Bool, in room: CatRoom) {
        stood[ObjectIdentifier(room)]?.isEnabled = isOn
    }
}

extension RoomKind {
    /// What a perf run marks the room on screen as.
    var perfName: String { self == .city ? "city room" : "room" }
}
