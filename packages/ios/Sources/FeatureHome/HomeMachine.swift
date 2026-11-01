import BilletKit
import Pet
import Wire

/// The home screen: which screen is up. The pet's own scenario runs in ``PetMachine``.
public enum HomeMachine: Machine {
  public enum Screen: Hashable, Sendable {
    case home
    case canvas
  }

  public struct State: Hashable, Sendable {
    public var screen: Screen
    public var pet: PetMachine.State

    public init(screen: Screen = .home, pet: PetMachine.State = PetMachine.State()) {
      self.screen = screen
      self.pet = pet
    }
  }

  public enum Output: Hashable, Sendable {
    case deliver([Stroke])
    case pet(PetMachine.Output)
  }

  public enum Event: Hashable, Sendable {
    case canvasOpened
    case canvasClosed
    case drawingSent([Stroke])
    case pet(PetMachine.Event)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    var next = state
    switch event {
    case .canvasOpened:
      next.screen = .canvas
      return (next, [])

    case .canvasClosed:
      next.screen = .home
      return (next, [])

    case .drawingSent(let strokes):
      next.screen = .home
      return (next, [.deliver(strokes)])

    case .pet(let event):
      let (pet, outputs) = PetMachine.transition(state.pet, event)
      next.pet = pet
      return (next, outputs.map(Output.pet))
    }
  }
}
