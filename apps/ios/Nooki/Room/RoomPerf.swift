import DecorInterface
import RealityKit
import RoomInterface

/// What the room's scene holds back: the Labs switches and the quality tier's plan, joined. All start off; flipping one
/// is a runtime toggle that can be flipped back.
struct RoomPerfSwitches: Equatable {
    var mergeFurniture = false
    var bakedBlobs = false
    var noSunShadow = false
    var fewerLights = false
    var noBloom = false
    var fullMeshes = false

    init() {}

    init(_ state: PerfLabMachine.State) {
        mergeFurniture = state.isOn(.mergeFurniture)
        bakedBlobs = state.isOn(.bakedBlobs)
        noSunShadow = state.isOn(.noSunShadow)
        fewerLights = state.isOn(.fewerLights)
        noBloom = state.isOn(.noBloom)
        fullMeshes = state.isOn(.fullMeshes)
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
    var pending: [ObjectIdentifier: Task<Void, Never>] = [:]

    /// Returns whether `next` differs from what was set.
    func set(_ next: RoomPerfSwitches) -> Bool {
        guard next != switches else { return false }
        switches = next
        return true
    }

    // MARK: Meshes

    /// Gives the room's boxes and spheres the tessellation the switch names, and every box and sphere built after it.
    func meshes(in room: CatRoom) {
        Meshes.smooth = !switches.fullMeshes
        Meshes.retessellate(room.root, smooth: !switches.fullMeshes)
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
}
