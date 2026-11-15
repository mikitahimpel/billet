import Foundation

/// How quickly Mochi gets about: her usual stroll about the room, and the eager pace of a game, where every wait
/// between moves is shorter and the moves themselves quicker. Seconds unless said otherwise.
struct CatPace: Equatable {
    /// Room units per second along the floor.
    var walkSpeed: Float
    /// From standing to full speed, and from it to a stop: about one stride.
    var rampTime: Float
    /// Radians per second turning on the spot.
    var turnRate: Float
    var standUp: Float
    var sitDown: Float
    /// Before a jump: gathering her weight back over the hind legs, the rump wiggle while she treads, and the still
    /// moment before the spring.
    var gather: Float
    var wiggle: ClosedRange<Float>
    var poise: Float
    /// Rump sways a second while she treads.
    var wiggleRate: Float
    /// Scales her time in the air and the landing.
    var flight: Float

    static let usual = CatPace(walkSpeed: 0.14, rampTime: 0.6, turnRate: 2.5, standUp: 0.7, sitDown: 0.8, gather: 0.35,
                               wiggle: 0.4...0.8, poise: 0.12, wiggleRate: 4.5, flight: 1)
    /// Chasing a dot or waiting on a bowl: up and down at once, a quick wiggle and a snappy spring.
    static let eager = CatPace(walkSpeed: 0.2, rampTime: 0.4, turnRate: 4.5, standUp: 0.4, sitDown: 0.45, gather: 0.2,
                               wiggle: 0.15...0.3, poise: 0.08, wiggleRate: 8, flight: 0.75)
}
