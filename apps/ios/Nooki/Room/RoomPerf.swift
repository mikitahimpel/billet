#if DEBUG || LABS_YES
import DecorInterface
import RealityKit
import RoomInterface

/// The Labs switches that change what the room's scene holds. All four start off; flipping one is a runtime toggle that
/// can be flipped back.
struct RoomPerfSwitches: Equatable {
    var mergeFurniture = false
    var bakedBlobs = false
    var noSunShadow = false
    var fewerLights = false
    var noBloom = false

    init() {}

    init(_ state: PerfLabMachine.State) {
        mergeFurniture = state.isOn(.mergeFurniture)
        bakedBlobs = state.isOn(.bakedBlobs)
        noSunShadow = state.isOn(.noSunShadow)
        fewerLights = state.isOn(.fewerLights)
        noBloom = state.isOn(.noBloom)
    }
}

/// A light's component and shadow taken off its entity by a switch, kept to put back.
struct StashedLight: Component {
    var point: PointLightComponent?
    var shadow: DirectionalLightComponent.Shadow?
}

#if compiler(>=6.4)
/// The bloom pass taken off a room's root by a switch, kept to put back.
@available(iOS 27, *)
struct StashedBloom: Component {
    var bloom: BloomComponent
}
#endif

/// Applies ``RoomPerfSwitches`` to the rooms and the furniture stage. Everything it changes is stashed on the entity it
/// changed, so switching off puts the scene back as the room built it.
@MainActor
final class RoomPerfCoordinator {
    private(set) var switches = RoomPerfSwitches()
    private var pending: [ObjectIdentifier: Task<Void, Never>] = [:]

    /// Returns whether `next` differs from what was set.
    func set(_ next: RoomPerfSwitches) -> Bool {
        guard next != switches else { return false }
        switches = next
        return true
    }

    // MARK: Lights

    /// The sun's shadow map, the point lights beyond the widest one and the bloom, as the switches say.
    func lights(in room: CatRoom) {
        #if compiler(>=6.4)
        if #available(iOS 27, *) {
            if switches.noBloom, let bloom = room.root.components[BloomComponent.self] {
                room.root.components.set(StashedBloom(bloom: bloom))
                room.root.components.remove(BloomComponent.self)
            } else if !switches.noBloom, let stash = room.root.components[StashedBloom.self] {
                room.root.components.set(stash.bloom)
                room.root.components.remove(StashedBloom.self)
            }
        }
        #endif
        var directional: [Entity] = []
        var points: [Entity] = []
        func visit(_ entity: Entity) {
            if entity.components.has(DirectionalLightComponent.self) { directional.append(entity) }
            if entity.components.has(PointLightComponent.self) || entity.components[StashedLight.self]?.point != nil {
                points.append(entity)
            }
            entity.children.forEach(visit)
        }
        visit(room.root)

        for sun in directional {
            var stash = sun.components[StashedLight.self] ?? StashedLight()
            if switches.noSunShadow {
                if let shadow = sun.components[DirectionalLightComponent.Shadow.self] {
                    stash.shadow = shadow
                    sun.components.set(stash)
                    sun.components.remove(DirectionalLightComponent.Shadow.self)
                }
            } else if let shadow = stash.shadow {
                sun.components.set(shadow)
                stash.shadow = nil
                sun.components.set(stash)
            }
        }

        // The widest light stays: its radius is fixed by the room, where its intensity follows the hour.
        func radius(_ entity: Entity) -> Float {
            (entity.components[PointLightComponent.self] ?? entity.components[StashedLight.self]?.point)?
                .attenuationRadius ?? 0
        }
        let keeper = points.max { radius($0) < radius($1) }
        for light in points where light !== keeper {
            var stash = light.components[StashedLight.self] ?? StashedLight()
            if switches.fewerLights {
                if let point = light.components[PointLightComponent.self] {
                    stash.point = point
                    light.components.set(stash)
                    light.components.remove(PointLightComponent.self)
                }
                light.isEnabled = false
            } else if let point = stash.point {
                if !light.components.has(PointLightComponent.self) { light.components.set(point) }
                stash.point = nil
                light.components.set(stash)
                light.isEnabled = true
            }
        }
    }

    // MARK: Furniture

    /// Brings the merged furniture and the baked contact shadow to the switches and the layout: put back at once when
    /// the player arranges or the layout changes, built again once the models are in and the layout has held still.
    func furniture(
        stage: Entity, room: DecorRoom, decor: RoomDecor,
        receiver: @escaping @MainActor () -> ImageBasedLightReceiverComponent?
    ) {
        let id = ObjectIdentifier(stage)
        pending[id]?.cancel()
        let wantMerged = switches.mergeFurniture && !decor.isArranging
        let wantBlobs = switches.bakedBlobs && !decor.isArranging
        if !wantMerged || FurnitureMerge.layout(in: stage) != decor.layout { FurnitureMerge.split(stage) }
        if !wantBlobs || ContactLayer.layout(in: stage) != decor.layout { ContactLayer.remove(stage) }
        guard (wantMerged && FurnitureMerge.layout(in: stage) == nil)
            || (wantBlobs && ContactLayer.layout(in: stage) == nil)
        else { return }
        pending[id] = Task {
            for attempt in 0..<30 {
                try? await Task.sleep(for: .milliseconds(attempt == 0 ? 400 : 1000))
                guard !Task.isCancelled else { return }
                guard let light = receiver(), Self.isStanding(stage, decor.layout.allPlacements(in: room).count) else { continue }
                if wantMerged, FurnitureMerge.layout(in: stage) == nil {
                    FurnitureMerge.merge(stage, layout: decor.layout, receiver: light)
                }
                if wantBlobs, ContactLayer.layout(in: stage) == nil { ContactLayer.bake(stage, layout: decor.layout) }
                return
            }
        }
    }

    /// Every piece of the layout has a holder with its model in.
    private static func isStanding(_ stage: Entity, _ count: Int) -> Bool {
        let holders = stage.children.filter { $0.name.hasPrefix("decor.") }
        guard holders.count == count else { return false }
        return holders.allSatisfy { holder in
            FurnitureMerge.models(under: holder).contains {
                $0.components[ModelComponent.self]?.materials.contains { !($0 is UnlitMaterial) } == true
                    || $0.components.has(MergedSource.self)
            }
        }
    }
}
#endif
