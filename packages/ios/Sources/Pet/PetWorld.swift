/// What a scene shows at any moment. Scenes read this and never change it.
public struct PetWorld: Hashable, Sendable {
  public enum Activity: Hashable, Sendable {
    case sleeping
    /// Waking, bringing the note, then sitting proudly.
    case delivering
    /// Going back to sleep. The next delivery starts only after this.
    case settling
  }

  public var activity: Activity
  /// Counts deliveries started so far, and names the current one in scene events.
  public var delivery: Int

  /// True while the partner has the app open. Scenes light the window and the pet looks at it.
  public var partnerHere: Bool

  public init(activity: Activity = .sleeping, delivery: Int = 0, partnerHere: Bool = false) {
    self.activity = activity
    self.delivery = delivery
    self.partnerHere = partnerHere
  }

  /// The delivery step alone. A scene paces and restarts its animation on this, so the partner
  /// coming or going does not cut a delivery short.
  public struct Step: Hashable, Sendable {
    public let activity: Activity
    public let delivery: Int
  }

  public var step: Step { Step(activity: activity, delivery: delivery) }

  /// True from the start of a delivery until the pet has finished showing it.
  public var noteArrived: Bool { activity == .delivering }
}
