import BilletKit
import Wire

/// The home screen: which screen is up, and where the cat is in delivering notes.
///
/// `noteArrived` is what the Rive scene is told. It stays true while the cat delivers and sits
/// proudly, then falls back to false so the cat settles and the next note can play from sleep.
public enum HomeMachine: Machine {
  public enum Screen: Hashable, Sendable {
    case home
    case canvas
  }

  public enum Cat: Hashable, Sendable {
    case sleeping
    /// Waking, carrying, hanging the note, then sitting proudly.
    case delivering
    /// Going back to sleep. `noteArrived` has to stay false until this has played.
    case settling
  }

  public struct State: Hashable, Sendable {
    public var screen: Screen
    public var cat: Cat
    /// Notes that arrived while the cat was busy, played one at a time.
    public var waitingNotes: Int

    public init(screen: Screen = .home, cat: Cat = .sleeping, waitingNotes: Int = 0) {
      self.screen = screen
      self.cat = cat
      self.waitingNotes = waitingNotes
    }

    public var noteArrived: Bool { cat == .delivering }
  }

  public enum Output: Hashable, Sendable {
    case deliver([Stroke])
    case holdDelivery
    case holdSettling
  }

  public enum Event: Hashable, Sendable {
    case canvasOpened
    case canvasClosed
    case drawingSent([Stroke])
    case noteArrived
    case deliveryPlayed
    case settlingPlayed
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    var next = state
    switch (state.cat, event) {
    case (.sleeping, .canvasOpened), (.delivering, .canvasOpened), (.settling, .canvasOpened):
      next.screen = .canvas
      return (next, [])

    case (.sleeping, .canvasClosed), (.delivering, .canvasClosed), (.settling, .canvasClosed):
      next.screen = .home
      return (next, [])

    case (.sleeping, .drawingSent(let strokes)),
      (.delivering, .drawingSent(let strokes)),
      (.settling, .drawingSent(let strokes)):
      next.screen = .home
      return (next, [.deliver(strokes)])

    case (.sleeping, .noteArrived):
      next.cat = .delivering
      return (next, [.holdDelivery])

    case (.delivering, .noteArrived), (.settling, .noteArrived):
      next.waitingNotes += 1
      return (next, [])

    case (.delivering, .deliveryPlayed):
      next.cat = .settling
      return (next, [.holdSettling])

    case (.settling, .settlingPlayed) where state.waitingNotes > 0:
      next.waitingNotes -= 1
      next.cat = .delivering
      return (next, [.holdDelivery])

    case (.settling, .settlingPlayed):
      next.cat = .sleeping
      return (next, [])

    case (.sleeping, .deliveryPlayed),
      (.settling, .deliveryPlayed),
      (.sleeping, .settlingPlayed),
      (.delivering, .settlingPlayed):
      return (next, [])
    }
  }
}
