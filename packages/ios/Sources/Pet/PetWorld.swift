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

  public init(activity: Activity = .sleeping, delivery: Int = 0) {
    self.activity = activity
    self.delivery = delivery
  }

  /// True from the start of a delivery until the pet has finished showing it.
  public var noteArrived: Bool { activity == .delivering }
}
