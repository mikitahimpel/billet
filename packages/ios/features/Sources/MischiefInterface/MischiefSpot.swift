/// The places the toy mouse can be hidden: the cat's spots in the living room. The raw values are the ids on the wire
/// and match the cat's own spot names.
public enum MischiefSpot: String, CaseIterable, Codable, Hashable, Sendable {
  case home
  case tree
  case sill
  case ball
  case basket
  case bowl
  case sofa
  case windowSeat
  case post
  case catBed
  case crate

  /// A chip's name.
  public var title: String {
    switch self {
    case .home: "Bed"
    case .tree: "Cat tree"
    case .sill: "Windowsill"
    case .ball: "Ball"
    case .basket: "Basket"
    case .bowl: "Bowl"
    case .sofa: "Sofa"
    case .windowSeat: "Window seat"
    case .post: "Scratching post"
    case .catBed: "Cat bed"
    case .crate: "Crate"
    }
  }

  /// After "hid the mouse".
  public var phrase: String {
    switch self {
    case .home: "by the bed"
    case .tree: "up the cat tree"
    case .sill: "on the windowsill"
    case .ball: "by the ball"
    case .basket: "in the basket"
    case .bowl: "by the food bowl"
    case .sofa: "on the sofa"
    case .windowSeat: "in the window seat"
    case .post: "by the scratching post"
    case .catBed: "in the cat bed"
    case .crate: "in the crate"
    }
  }

  public var symbol: String {
    switch self {
    case .home: "bed.double.fill"
    case .tree: "tree.fill"
    case .sill: "window.shade.open"
    case .ball: "soccerball"
    case .basket: "basket.fill"
    case .bowl: "fork.knife"
    case .sofa: "sofa.fill"
    case .windowSeat: "chair.lounge.fill"
    case .post: "pawprint.fill"
    case .catBed: "moon.zzz.fill"
    case .crate: "shippingbox.fill"
    }
  }
}
