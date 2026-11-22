/// How near a look is to the mouse.
public enum Warmth: Int, Comparable, Sendable {
  case cold
  case cool
  case warm
  case hot

  public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// What the cat does when the seeker looks somewhere. She knows where the mouse is and keeps no secrets: the
/// warmer the look, the plainer she gives it away.
public enum MischiefHint: Equatable, Sendable {
  /// Cold: she yawns and looks the other way.
  case away
  /// Cool: an ear flicks, toward nothing in particular.
  case curious
  /// Warm: her ears go up and her head turns toward the mouse.
  case turns(toward: MischiefSpot)
  /// Hot: she goes over to it and sniffs.
  case sniffs(at: MischiefSpot)
  /// After a few misses: she walks to it and sits by it, plainly.
  case leads(to: MischiefSpot)
  /// Found: she pounces on it.
  case pounces(on: MischiefSpot)
}

/// Where the cat's spots are on the room's floor, in the room's own metres, as the room tells it.
public struct MischiefSpotMap: Equatable, Sendable {
  public struct Point: Equatable, Sendable {
    public var x: Double
    public var z: Double

    public init(x: Double, z: Double) {
      self.x = x
      self.z = z
    }
  }

  public var points: [MischiefSpot: Point]

  public init(_ points: [MischiefSpot: Point] = [:]) {
    self.points = points
  }

  /// The spots a mouse can be hidden at, in the order the picker shows them.
  public var spots: [MischiefSpot] {
    MischiefSpot.allCases.filter { points[$0] != nil }
  }

  /// A look at `guess` while the mouse is at `target`. A spot the room does not know reads as cool.
  public func warmth(guess: MischiefSpot, target: MischiefSpot) -> Warmth {
    guard let a = points[guess], let b = points[target] else { return .cool }
    let distance = ((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)).squareRoot()
    switch distance {
    case ..<0.25: return .hot
    case ..<0.5: return .warm
    case ..<0.8: return .cool
    default: return .cold
    }
  }
}
