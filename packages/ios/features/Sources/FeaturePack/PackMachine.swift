import BilletKit
import PackInterface

/// Packing one suitcase for two, on one phone passed from hand to hand. The first packs their three things
/// knowing only the names of the other's; the second fits theirs round them and the cat goes in last. When
/// it will not go, the suitcase is sent back to be packed again. Nothing is timed and nothing is lost.
public enum PackMachine: Machine {
  /// What stays the same through a round, and what is counted.
  public struct Game: Equatable, Sendable {
    public let seed: UInt64
    /// Suitcases closed since the screen opened.
    public var round = 0
    /// Times this suitcase went back to the first packer.
    public var repacks = 0

    public init(seed: UInt64) { self.seed = seed }

    var level: PackLevel { PackLevel.make(seed: seed &+ UInt64(round)) }
  }

  public struct Held: Equatable, Sendable {
    public let id: Int
    /// Quarter turns from how the piece was handed over.
    public var turns: Int
  }

  /// What the cat makes of the suitcase when asked.
  public enum Nose: Equatable, Sendable {
    case fits, tooTight
  }

  public struct Turn: Equatable, Sendable {
    public var game: Game
    public var suitcase: PackCase
    public let packer: PackPacker
    public var held: Held?
    /// Why the last tap put nothing down; nil once one does.
    public var refused: PackCase.Problem?
    /// Her answer, until the suitcase changes.
    public var nose: Nose?

    public init(game: Game, suitcase: PackCase, packer: PackPacker) {
      self.game = game
      self.suitcase = suitcase
      self.packer = packer
    }

    public func canMove(_ piece: PackPiece) -> Bool {
      switch packer {
      case .first: piece.belongs(to: .first)
      case .second: piece.belongs(to: .second) || piece.isCat
      }
    }

    /// The pieces this packer still has in hand, the cat last.
    public var tray: [PackPiece] { suitcase.loose.filter(canMove) }

    /// The other's things, which the first packer knows only by name.
    public var unseen: [PackPiece] {
      switch packer {
      case .first: suitcase.level.pieces.filter { $0.belongs(to: .second) }
      case .second: []
      }
    }

    public var heldPiece: PackPiece? { held.flatMap { suitcase.level.piece($0.id) } }

    public var canHandOver: Bool {
      packer == .first && !suitcase.loose.contains { $0.belongs(to: .first) }
    }

    public var canClose: Bool {
      packer == .second && !suitcase.loose.contains { !$0.isCat }
    }
  }

  public struct Handover: Equatable, Sendable {
    public let game: Game
    public let suitcase: PackCase
    public let to: PackPacker
  }

  public enum Ending: Equatable, Sendable {
    /// Everything in, the cat too.
    case snug
    /// The things are in and she sits on the lid.
    case catOnTop
  }

  public struct Closed: Equatable, Sendable {
    public let game: Game
    public let suitcase: PackCase
    public let ending: Ending
  }

  public enum State: Equatable, Sendable {
    case packing(Turn)
    /// The phone is on its way to the other packer.
    case handover(Handover)
    case closed(Closed)
  }

  public enum Event: Equatable, Sendable {
    /// A piece taken from the tray.
    case picked(Int)
    case turned
    /// A square of the suitcase: puts the held piece there, or picks up the one that lies there.
    case tapped(PackCell)
    /// The held piece goes back to the tray.
    case dropped
    case askedCat
    case handedOver
    /// The second packer cannot make it fit: their things come out and the first packs again.
    case sentBack
    case took
    case zipped
    /// A new suitcase, the other one packing first.
    case again
  }

  public enum Feel: Equatable, Sendable {
    case put, refused, zipped
  }

  public enum Output: Equatable, Sendable {
    case felt(Feel)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.packing(var turn), .picked(let id)):
      guard let piece = turn.suitcase.level.piece(id), turn.canMove(piece) else {
        return (state, [])
      }
      turn.suitcase.lift(id)
      turn.held = Held(id: id, turns: 0)
      turn.refused = nil
      turn.nose = nil
      return (.packing(turn), [])

    case (.packing(var turn), .turned):
      guard let held = turn.held else { return (state, []) }
      turn.held = Held(id: held.id, turns: (held.turns + 1) % 4)
      turn.refused = nil
      return (.packing(turn), [])

    case (.packing(var turn), .tapped(let cell)):
      guard let held = turn.held, let piece = turn.heldPiece else {
        guard let id = turn.suitcase.covered[cell], let piece = turn.suitcase.level.piece(id),
          turn.canMove(piece)
        else { return (state, []) }
        let turns = turn.suitcase.placed[id]?.turns ?? 0
        turn.suitcase.lift(id)
        turn.held = Held(id: id, turns: turns)
        turn.refused = nil
        turn.nose = nil
        return (.packing(turn), [])
      }
      let anchor = piece.shape.turned(held.turns).anchor
      let placement = PackPlacement(
        at: PackCell(x: cell.x - anchor.x, y: cell.y - anchor.y), turns: held.turns)
      turn.refused = turn.suitcase.put(piece, placement)
      guard turn.refused == nil else { return (.packing(turn), [.felt(.refused)]) }
      turn.held = nil
      turn.nose = nil
      return (.packing(turn), [.felt(.put)])

    case (.packing(var turn), .dropped):
      turn.held = nil
      turn.refused = nil
      return (.packing(turn), [])

    case (.packing(var turn), .askedCat):
      turn.nose = turn.suitcase.stillFits ? .fits : .tooTight
      return (.packing(turn), [])

    case (.packing(let turn), .handedOver):
      guard turn.canHandOver else { return (state, []) }
      return (.handover(Handover(game: turn.game, suitcase: turn.suitcase, to: .second)), [])

    case (.packing(let turn), .sentBack):
      guard turn.packer == .second else { return (state, []) }
      var suitcase = turn.suitcase
      for piece in suitcase.level.pieces where !piece.belongs(to: .first) {
        suitcase.lift(piece.id)
      }
      var game = turn.game
      game.repacks += 1
      return (.handover(Handover(game: game, suitcase: suitcase, to: .first)), [])

    case (.packing(let turn), .zipped):
      guard turn.canClose else { return (state, []) }
      let cat = turn.suitcase.level.pieces.first { $0.isCat }
      let ending: Ending = cat.map { turn.suitcase.isIn($0.id) } == true ? .snug : .catOnTop
      let closed = Closed(game: turn.game, suitcase: turn.suitcase, ending: ending)
      return (.closed(closed), [.felt(.zipped)])

    case (.handover(let handover), .took):
      let turn = Turn(game: handover.game, suitcase: handover.suitcase, packer: handover.to)
      return (.packing(turn), [])

    case (.closed(let closed), .again):
      var game = Game(seed: closed.game.seed)
      game.round = closed.game.round + 1
      return (.packing(Turn(game: game, suitcase: PackCase(level: game.level), packer: .first)), [])

    case (.packing, .took), (.packing, .again),
      (.handover, .picked), (.handover, .turned), (.handover, .tapped), (.handover, .dropped),
      (.handover, .askedCat), (.handover, .handedOver), (.handover, .sentBack),
      (.handover, .zipped), (.handover, .again),
      (.closed, .picked), (.closed, .turned), (.closed, .tapped), (.closed, .dropped),
      (.closed, .askedCat), (.closed, .handedOver), (.closed, .sentBack), (.closed, .took),
      (.closed, .zipped):
      return (state, [])
    }
  }

  public static func opening(seed: UInt64) -> State {
    let game = Game(seed: seed)
    return .packing(Turn(game: game, suitcase: PackCase(level: game.level), packer: .first))
  }
}

public typealias PackStore = Store<PackMachine>

extension Store where M == PackMachine {
  /// `feel` plays a put, a refusal or the zip as a haptic; the machine needs no other work done.
  @MainActor
  public static func pack(
    seed: UInt64, feel: @escaping @Sendable (PackMachine.Feel) async -> Void = { _ in }
  ) -> PackStore {
    Store(initial: PackMachine.opening(seed: seed)) { output in
      switch output {
      case .felt(let felt):
        await feel(felt)
        return nil
      }
    }
  }
}
