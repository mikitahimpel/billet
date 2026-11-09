import Foundation

/// Brushing the cat: strokes head to tail fill the groom bar and make her content; a stroke
/// against the grain makes her flinch, and the hint says which way.
public struct BrushStrokes: Equatable, Sendable {
  public enum Reaction: Equatable, Sendable {
    /// A good stroke; `purrs` when it is the first in a while, for her to start purring.
    case enjoys(purrs: Bool)
    /// Brushed the wrong way for a while: ears back.
    case flinches
  }

  /// The cat's length in meters.
  public let length: Double

  public private(set) var groom: Double = 0
  /// 0...1: how content she is now; it fades when the strokes stop.
  public private(set) var content: Double = 0
  /// Fur shed so far, a tuft per good little stretch of stroke.
  public private(set) var tufts = 0

  private var against: Double = 0
  private var sinceGood = Double.infinity
  private var shedding: Double = 0

  public init(length: Double) {
    self.length = length
  }

  public var isDone: Bool { groom >= 1 }
  /// Purring while strokes keep coming.
  public var isPurring: Bool { sinceGood < 0.6 }

  /// One step of a stroke, `distance` meters across her fur; `fit` is the cosine between the
  /// stroke and her grain (1 head to tail, -1 tail to head).
  public mutating func stroke(distance: Double, fit: Double) -> Reaction? {
    guard distance >= 0.0008 else { return nil }
    if fit > 0.35 {
      groom = min(1, groom + distance / (4 * length))
      content = min(1, content + distance / (0.5 * length))
      let purrs = sinceGood > 0.8
      sinceGood = 0
      shedding += distance
      while shedding >= 0.006 {
        shedding -= 0.006
        tufts += 1
      }
      return .enjoys(purrs: purrs)
    }
    if fit < -0.35 {
      against += distance
      if against > 0.04 {
        against = 0
        content = max(0, content - 0.5)
        return .flinches
      }
    }
    return nil
  }

  /// Time passes: contentment fades without strokes.
  public mutating func update(dt: Double) {
    sinceGood += dt
    if !isPurring { content = max(0, content - dt * 0.12) }
  }

  public static let wrongWay = "Other way: with the fur, head to tail"
}
