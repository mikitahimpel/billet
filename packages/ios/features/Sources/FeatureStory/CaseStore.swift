import BilletKit
import Foundation
import StoryInterface
import Transport
import Wire

public typealias CaseStore = Store<CaseMachine>

/// What the case's outputs run on.
public struct StoryServices: Sendable {
  public var client: StoryClient
  public var now: @Sendable () -> Date
  public var events: EventReporter

  public init(
    client: StoryClient, now: @escaping @Sendable () -> Date = { Date() },
    events: EventReporter = .none
  ) {
    self.client = client
    self.now = now
    self.events = events
  }
}

extension Store where M == CaseMachine {
  /// A store with no case until `.enabled`.
  @MainActor
  public static func story(_ services: StoryServices) -> CaseStore {
    CaseStore(initial: .unavailable) { output in
      switch output {
      case .fetch:
        guard let marks = await services.client.fetch() else { return nil }
        return .fetched(marks, at: services.now())
      case .mark(let episode, let kind, let ref):
        guard let marks = await services.client.mark(episode, kind, ref) else { return .markFailed }
        await report(kind, ref: ref, episode: episode, services)
        return .marked(marks, at: services.now())
      }
    }
  }

  @MainActor
  private static func report(
    _ kind: CaseMark.Kind, ref: String, episode: String, _ services: StoryServices
  ) {
    switch (kind, ref == Episode.endingRef) {
    case (.found, false): services.events(.clueFound, detail: ref)
    case (.found, true): services.events(.caseSolved, detail: episode)
    case (.named, _): break
    }
  }
}
