import Foundation
import RealityKit
import UIKit
import WidgetBridge

/// How a room's static pieces are made. Set on a room's pivot, it reaches every primitive built under it.
struct ShellMode: Component {
    enum Kind {
        /// The static pieces are not built: a baked model stands in for them.
        case baked
        /// The static pieces are built as usual and tagged, for the bake's export (`ShellExport`).
        case export
    }

    let kind: Kind
}

/// On a subtree that stays built live in any mode: the garland's photos, the clock's hands.
struct ShellLive: Component {}

/// The tint the room last asked of its shell, kept for a shell that loads after it.
struct ShellTint: Component { let color: UIColor }

/// A primitive the baked model replaces; only tagged while exporting.
struct ShellPart: Component {}

extension Entity {
    fileprivate var shellKind: ShellMode.Kind? {
        var node: Entity? = self
        while let n = node {
            if n.components.has(ShellLive.self) { return nil }
            if let mode = n.components[ShellMode.self] { return mode.kind }
            node = n.parent
        }
        return nil
    }

    /// Glowing parts (bulbs, flames, lamp shades) change as the room does, so they are always built.
    private static func glows(_ material: some Material) -> Bool {
        guard let pbr = material as? PhysicallyBasedMaterial else { return false }
        return pbr.emissiveIntensity > 0
    }

    func skipsForShell(_ material: some Material) -> Bool {
        shellKind == .baked && !Self.glows(material)
    }

    func tagForShell(_ entity: Entity, _ material: some Material) {
        if shellKind == .export, !Self.glows(material) { entity.components.set(ShellPart()) }
    }
}

/// The baked shell experiment: each room's static walls, floor and furniture as one lightmapped model.
/// `docs/baked-shell.md` says how it is made and how to take it out.
enum BakedShell {
    static let labsKey = "labs.roomShell"
    /// Set by the bake's export to build the rooms with their static parts tagged.
    static let exportKey = "bake.export"

    @MainActor
    static func resolved(_ defaults: UserDefaults = .standard) -> RoomShell {
        let remote = defaults.data(forKey: RoomsChoice.remoteKey)
            .flatMap { try? JSONDecoder().decode(RemoteFlags.self, from: $0) } ?? RemoteFlags()
        let labs = defaults.string(forKey: labsKey).flatMap(RoomShell.init(remoteVariant:))
        return RoomShell.resolved(labs: labs, remote: remote)
    }

    /// The colour the unlit shell is multiplied by: the lightmap holds one state of the day, this is the rest.
    static func tint(_ sample: Daylight.Sample) -> UIColor {
        let level = 0.3 + 0.7 * min(sample.env / 0.85, 1)
        let sky = simd_mix(SIMD3<Float>(repeating: 1), sample.horizon, SIMD3(repeating: 0.3))
        return Daylight.color(simd_clamp(sky * level, .zero, .one))
    }
}

extension CatRoom {
    static let shellName = "BakedShell"

    /// The one line each room's init calls: builds the room's static parts as before, or not at all when the baked
    /// model is on, and loads that model in the background. Does nothing for the live shell.
    @MainActor
    func useBakedShell(named model: String, defaults: UserDefaults = .standard) {
        if defaults.bool(forKey: BakedShell.exportKey) {
            pivot.components.set(ShellMode(kind: .export))
            return
        }
        guard BakedShell.resolved(defaults) == .baked else { return }
        pivot.components.set(ShellMode(kind: .baked))
        Task { [weak self] in
            guard let shell = try? await Entity(named: model, in: .main) else {
                print("\(model) failed to load")
                return
            }
            guard let self else { return }
            shell.name = Self.shellName
            let tint = pivot.components[ShellTint.self]?.color ?? .white
            shell.forEachDescendant { entity in
                guard var mesh = entity.components[ModelComponent.self] else { return }
                mesh.materials = mesh.materials.map { Self.unlit($0, tint: tint) }
                entity.components.set(mesh)
            }
            pivot.addChild(shell)
        }
    }

    /// Whether the baked shell is in this room.
    var isBaked: Bool { pivot.components[ShellMode.self]?.kind == .baked }

    /// Multiplies the baked shell by `tint`, for the time of day.
    func tintShell(_ tint: UIColor) {
        pivot.components.set(ShellTint(color: tint))
        guard let shell = pivot.findEntity(named: Self.shellName) else { return }
        shell.forEachDescendant { entity in
            guard var mesh = entity.components[ModelComponent.self] else { return }
            mesh.materials = mesh.materials.map { Self.unlit($0, tint: tint) }
            entity.components.set(mesh)
        }
    }

    private static func unlit(_ material: any Material, tint: UIColor) -> any Material {
        var texture: MaterialParameters.Texture?
        if let pbr = material as? PhysicallyBasedMaterial { texture = pbr.baseColor.texture }
        if let unlit = material as? UnlitMaterial { texture = unlit.color.texture }
        var result = UnlitMaterial(applyPostProcessToneMap: false)
        result.color = .init(tint: tint, texture: texture)
        return result
    }
}
