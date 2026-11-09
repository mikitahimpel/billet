import BilletKit

/// The delivery scenario: a note wakes the pet, the scene plays it, the pet settles. Each step
/// that waits on a scene starts a deadline that sends the scene's own event, so a hung scene
/// cannot stall the pet; a finished step ignores it, as the delivery or activity no longer match.
public enum PetMachine: Machine {
  public struct State: Hashable, Sendable {
    public var world: PetWorld
    /// Notes that arrived while the pet was busy, played one at a time.
    public var waitingNotes: Int

    public init(world: PetWorld = PetWorld(), waitingNotes: Int = 0) {
      self.world = world
      self.waitingNotes = waitingNotes
    }
  }

  public enum Output: Hashable, Sendable {
    case deliveryDeadline(delivery: Int)
    case settlingDeadline(delivery: Int)
  }

  public enum Event: Hashable, Sendable {
    case noteArrived
    case deliveryFinished(delivery: Int)
    case settled(delivery: Int)
    case partnerPresence(Bool)
    case streakChanged(Int)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    var next = state
    switch event {
    case .partnerPresence(let here):
      next.world.partnerHere = here
      return (next, [])
    case .streakChanged(let days):
      next.world.streak = max(0, days)
      return (next, [])
    case .noteArrived, .deliveryFinished, .settled:
      break
    }
    switch (state.world.activity, event) {
    case (.sleeping, .noteArrived):
      return startDelivery(next)

    case (.delivering, .noteArrived), (.settling, .noteArrived):
      next.waitingNotes += 1
      return (next, [])

    case (.delivering, .deliveryFinished(let delivery)) where delivery == state.world.delivery:
      next.world.activity = .settling
      return (next, [.settlingDeadline(delivery: delivery)])

    case (.settling, .settled(let delivery))
    where delivery == state.world.delivery && state.waitingNotes > 0:
      next.waitingNotes -= 1
      return startDelivery(next)

    case (.settling, .settled(let delivery)) where delivery == state.world.delivery:
      next.world.activity = .sleeping
      return (next, [])

    case (.sleeping, .deliveryFinished), (.delivering, .deliveryFinished),
      (.settling, .deliveryFinished), (.sleeping, .settled), (.delivering, .settled),
      (.settling, .settled), (_, .partnerPresence), (_, .streakChanged):
      return (next, [])
    }
  }

  private static func startDelivery(_ state: State) -> (State, [Output]) {
    var next = state
    next.world.activity = .delivering
    next.world.delivery += 1
    return (next, [.deliveryDeadline(delivery: next.world.delivery)])
  }
}
