#if DEBUG || LABS_YES
import DecorInterface
import RealityKit

extension RoomPerfCoordinator {
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
                let light = receiver()
                // Without ambient light after a few seconds the room has none to wait for (it can't be made on every machine).
                guard light != nil || attempt >= 4, Self.isStanding(stage, decor.layout.allPlacements(in: room).count) else { continue }
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
