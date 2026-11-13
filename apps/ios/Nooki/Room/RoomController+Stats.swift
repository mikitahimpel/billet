#if DEBUG || LABS_YES
import Foundation
import RealityKit
import RoomInterface

/// Labs → Performance reads the room's cost through here: a plain value, so the lab never holds a scene.
extension RoomController {
    func roomStats(tier: RoomQualityTier) -> RoomStats? {
        guard let scene = current else { return nil }
        let name =
            switch shown {
            case .home: "living"
            case .city: "bedroom"
            case .board: "board"
            }
        var stats = RoomStats(walking: scene.root, room: name, tier: tier.title)
        if SplatLoader.isSupported, let walker = scene.walker {
            let rigs: [(CatRig, String)] =
                [(walker.standing, "MochiStanding"), (walker.seated, "Mochi")]
                + walker.bodies.map { ($0.value, $0.key == .sleep ? "MochiSleep" : "MochiLoaf") }
            let drawn = rigs.filter { $0.0.entity?.isActive == true }
            let counts = drawn.map { Self.splatCount(in: $0.1) }
            stats.setSplats(
                entities: drawn.count, full: counts.contains(nil) ? nil : counts.compactMap { $0 }.reduce(0, +),
                keep: SplatDetail.chosen().keep)
        }
        stats.writeRates = SceneWrites.drainRates()
        return stats
    }

    /// The splats a PLY file holds, from its header alone.
    private static func splatCount(in file: String) -> Int? {
        guard let url = Bundle.main.url(forResource: file, withExtension: "ply"),
            let handle = try? FileHandle(forReadingFrom: url), let head = try? handle.read(upToCount: 1024)
        else { return nil }
        try? handle.close()
        let text = String(decoding: head, as: UTF8.self)
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("element vertex ") }) else { return nil }
        return Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces))
    }
}
#endif
