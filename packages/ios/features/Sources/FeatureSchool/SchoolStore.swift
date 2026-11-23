import BilletKit
import Foundation
import SchoolInterface
import Transport
import Wire

public typealias SchoolStore = Store<SchoolMachine>

/// Where the school's moves reach the room's cat. The room is attached once it is on screen;
/// before that a move goes nowhere.
@MainActor
public final class SchoolStage {
  public var perform: ((SchoolMove) -> Void)?

  public init() {}

  func play(_ move: SchoolMove) { perform?(move) }
}

/// What the school's outputs run on.
public struct SchoolServices: Sendable {
  public var client: SchoolClient
  public var stage: SchoolStage
  public var events: EventReporter
  /// The time one move of a routine is given before the next starts.
  public var beat: Duration

  public init(
    client: SchoolClient, stage: SchoolStage, events: EventReporter = .none,
    beat: Duration = .seconds(3)
  ) {
    self.client = client
    self.stage = stage
    self.events = events
    self.beat = beat
  }
}

extension Store where M == SchoolMachine {
  /// A store with no school until `.enabled`.
  @MainActor
  public static func school(_ services: SchoolServices) -> SchoolStore {
    SchoolStore(initial: .unavailable) { output in
      switch output {
      case .fetch:
        return await services.client.fetch().map { .fetched($0) }
      case .perform(let move):
        await services.stage.play(move)
        return nil
      case .play(let moves):
        for move in moves {
          await services.stage.play(move)
          try? await Task.sleep(for: services.beat)
        }
        return nil
      case .teach(let trick, let star):
        guard let book = await services.client.teach(trick, star) else { return .saveFailed }
        await services.events(.trickTaught, detail: trick.rawValue)
        return .saved(book)
      case .send(let take):
        guard let book = await services.client.send(take) else { return .routine(.sendFailed) }
        await services.events(.routineSent)
        return .routineSent(book)
      case .count(let trick):
        await services.events(.trickDone, detail: trick.rawValue)
        return nil
      }
    }
  }
}
