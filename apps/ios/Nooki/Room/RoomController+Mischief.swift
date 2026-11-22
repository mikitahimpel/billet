import MischiefInterface
import Pet
import RoomInterface

/// What the room tells the shell about the toy mouse game, and how the cat answers it.
extension RoomController {
    /// The cat's spots in the living room, told when they change.
    func tellMischiefSpots() {
        guard let home else { return }
        var points: [MischiefSpot: MischiefSpotMap.Point] = [:]
        for (spot, destination) in home.catSpots {
            guard let spot = MischiefSpot(rawValue: spot.rawValue), let at = destination.path.last?.at else { continue }
            points[spot] = .init(x: Double(at.x), z: Double(at.z))
        }
        points[.home] = .init(x: Double(home.bedCenter.x), z: Double(home.bedCenter.z))
        let map = MischiefSpotMap(points)
        guard map != spotsTold else { return }
        spotsTold = map
        emit.yield(.spotsKnown(map))
    }

    func mischief(_ hint: MischiefHint) { current?.director?.mischief(hint) }
}
