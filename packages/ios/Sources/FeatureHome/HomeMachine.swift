import BilletKit
import Foundation
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
    /// Drawings not yet carried in, oldest first.
    public var inbox: [[Stroke]]
    /// The drawing the pet is hanging, or hung last.
    public var hungDrawing: [Stroke]?

    public init(
      screen: Screen = .home,
      pet: PetMachine.State = PetMachine.State(),
      inbox: [[Stroke]] = [],
      hungDrawing: [Stroke]? = nil
    ) {
      self.screen = screen
      self.pet = pet
      self.inbox = inbox
      self.hungDrawing = hungDrawing
    }
  }

  public enum Output: Hashable, Sendable {
    case deliver([Stroke], id: UUID)
    case pet(PetMachine.Output)
  }

  public enum Event: Hashable, Sendable {
    case canvasOpened
    case canvasClosed
    case drawingSent([Stroke], id: UUID)
    case noteReceived([Stroke])
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

    case .drawingSent(let strokes, let id):
      next.screen = .home
      return (next, [.deliver(strokes, id: id)])

    case .noteReceived(let strokes):
      next.inbox.append(strokes)
      return transition(next, .pet(.noteArrived))

    case .pet(let event):
      let (pet, outputs) = PetMachine.transition(state.pet, event)
      next.pet = pet
      if pet.world.delivery != state.pet.world.delivery, !next.inbox.isEmpty {
        next.hungDrawing = next.inbox.removeFirst()
      }
      return (next, outputs.map(Output.pet))
    }
  }
}
