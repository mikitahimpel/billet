import Foundation

/// What the cat does once a bowl is served: a bite-by-bite meal and, after an overfeed, a yawn into a loaf and a slow
/// blink now and then, with her staying where she sits.
public struct FeedAftermath: Equatable, Sendable {
  public enum Act: Equatable, Sendable {
    case yawn
    case loaf
    case slowBlink
  }

  /// Seconds after serving before a stuffed cat sinks into a loaf.
  public static let loafAfter: Double = 2.5
  public static let blinkEvery: Double = 2.2

  public let stuffed: Bool
  public private(set) var time: Double = 0
  public private(set) var loafed = false
  private var sinceBlink: Double = 0

  public init(stuffed: Bool) {
    self.stuffed = stuffed
  }

  /// The acts due after `dt` more seconds. A cat that ate the right amount has none.
  public mutating func advance(_ dt: Double) -> [Act] {
    time += max(dt, 0)
    guard stuffed, time > Self.loafAfter else { return [] }
    var acts: [Act] = []
    if !loafed {
      loafed = true
      acts += [.loaf, .yawn]
    }
    sinceBlink += max(dt, 0)
    if sinceBlink > Self.blinkEvery {
      sinceBlink = 0
      acts.append(.slowBlink)
    }
    return acts
  }
}

/// Whether a point of the room, projected on screen, is still where the player can see it.
public enum OnScreen {
  /// `point` is nil for behind the camera. `inset` keeps it off the very edge.
  public static func contains(_ point: CGPoint?, in size: CGSize, inset: CGFloat = 0) -> Bool {
    guard let point, size.width > 0, size.height > 0 else { return false }
    return point.x >= inset && point.x <= size.width - inset
      && point.y >= inset && point.y <= size.height - inset
  }
}
