import FeatureGames
import GamesInterface
import RealityKit
import SwiftUI
import UIKit

/// One finger on the game: where it is on screen, and its ray into the room's pivot space.
struct GameTouch {
    let point: CGPoint
    let origin: SIMD3<Float>
    let direction: SIMD3<Float>

    /// Where the ray meets the level plane at height `y`, or nil when it runs away from it.
    func onPlane(y: Float) -> SIMD3<Float>? {
        guard abs(direction.y) > 1e-4 else { return nil }
        let t = (y - origin.y) / direction.y
        return t > 0 ? origin + direction * t : nil
    }

    func distance(to p: SIMD3<Float>) -> Float {
        let v = p - origin
        return simd_length(v - direction * max(simd_dot(v, direction), 0))
    }
}

/// A game played in the room: it builds its props under `root`, answers touches and moves on each frame, telling
/// the controller what to show through `deck`.
@MainActor
protocol GameStage: AnyObject {
    /// In the pivot's space.
    var focus: [SIMD3<Float>] { get }
    func began(_ touch: GameTouch)
    func moved(_ touch: GameTouch)
    func ended(_ touch: GameTouch?)
    func update(_ dt: Float)
    /// The overlay's button (Feed, Serve), if the game has one now.
    var action: String? { get }
    func act()
    /// Gives the room back: props gone, the cat on her way home.
    func tearDown()
}

extension GameStage {
    var action: String? { nil }
    func act() {}
}

/// What a game shows over the room and the feel of it in the hand.
@MainActor
@Observable
final class GameDeck {
    var hint: String?
    /// Hidden with nil.
    var bar: (value: Double, label: String)?
    var result: GameResult?

    /// Sets `bar` when it has moved by a percent, reached an end or changed its label: a stage reports it every
    /// frame, and each write re-renders the bar.
    func show(_ value: Double, _ label: String) {
        if let bar, bar.label == label, abs(bar.value - value) < 0.01, value > 0, value < 1 { return }
        bar = (value, label)
    }
    /// Where a point in the pivot's space shows on screen, and how many points a meter there spans.
    @ObservationIgnored var project: (SIMD3<Float>) -> CGPoint? = { _ in nil }
    @ObservationIgnored var pointsPerMeter: (SIMD3<Float>) -> CGFloat = { _ in 1 }
    @ObservationIgnored private var hintAge: Float = 0
    @ObservationIgnored private var hintFor: Float = .infinity
    @ObservationIgnored private let light = UIImpactFeedbackGenerator(style: .light)
    @ObservationIgnored private let soft = UIImpactFeedbackGenerator(style: .soft)
    @ObservationIgnored private let firm = UIImpactFeedbackGenerator(style: .medium)

    /// Shows `text`, for `seconds` or until replaced.
    func say(_ text: String?, for seconds: Float = .infinity) {
        hint = text
        hintAge = 0
        hintFor = seconds
    }

    func tick(_ dt: Float) {
        hintAge += dt
        if hintAge > hintFor { hint = nil; hintFor = .infinity }
    }

    func tap(_ intensity: CGFloat = 0.6) { light.impactOccurred(intensity: intensity) }
    func stroke() { soft.impactOccurred(intensity: 0.5) }
    func thump() { firm.impactOccurred() }
}

/// Where each room has the games played: a patch of open floor near the camera, the cat's seat there, and how big
/// she is. In the pivot's space, y the floor's top.
struct GameSpots {
    let center: SIMD3<Float>
    let floor: Float
    /// Open floor for the laser dot.
    let area: FloorArea
    /// Meters.
    let length: Float
    /// Across the screen from left to right, and toward the camera, along the floor at the room's home view.
    let right: SIMD3<Float>
    let toward: SIMD3<Float>

    init(room: CatRoom) {
        let direction = room.framing.direction
        toward = simd_normalize(SIMD3(direction.x, 0, direction.z))
        right = simd_normalize(simd_cross([0, 1, 0], toward))
        if room is TabletopRoom {
            floor = TabletopRoom.floorTop
            center = [0, floor, 0.02]
            area = FloorArea(x: -0.25...0.25, z: -0.15...0.3)
            length = 0.22
        } else if room is CityRoomScene {
            floor = 0.014
            center = [0.02, floor, 0.16]
            area = FloorArea(x: -0.3...0.25, z: -0.05...0.38)
            length = 0.2
        } else {
            floor = 0.023
            center = [0.3, floor, 0.12]
            area = FloorArea(x: 0.18...0.47, z: -0.08...0.3)
            length = 0.22
        }
    }

    /// `x` across the screen and `z` toward the camera from the center, on the floor.
    func at(_ x: Float, _ z: Float, up y: Float = 0) -> SIMD3<Float> {
        center + right * x + toward * z + [0, y, 0]
    }

    /// The yaw that faces her from `from` toward `to` (0 faces -z).
    static func yaw(from: SIMD3<Float>, to: SIMD3<Float>) -> Float {
        atan2(-(to.x - from.x), -(to.z - from.z))
    }
}

extension CatRoom {
    /// Sends Mochi to `spot` facing `facing` and sitting there; `play` adds a couple of paw pats as she lands.
    func send(to spot: SIMD3<Float>, facing yaw: Float, id: String, play: Bool = false, arrive: (() -> Void)? = nil) {
        walker?.go(to: CatWalker.Destination(
            id: id, path: [.init(at: spot, move: .jump)], rest: yaw, play: play, arrive: arrive))
    }
}
