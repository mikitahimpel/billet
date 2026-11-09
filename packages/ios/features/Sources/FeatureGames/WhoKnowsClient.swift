import BilletKit
import Transport
import Wire

/// The pair's Who knows who round in its room. Every call answers today's round as this user sees
/// it after it.
public struct WhoKnowsClient: Sendable {
  public var fetch: @Sendable () async throws(TransportError) -> GuessResponse
  public var answer: @Sendable (GuessAnswerRequest) async throws(TransportError) -> GuessResponse

  public init(
    fetch: @escaping @Sendable () async throws(TransportError) -> GuessResponse,
    answer: @escaping @Sendable (GuessAnswerRequest) async throws(TransportError) -> GuessResponse
  ) {
    self.fetch = fetch
    self.answer = answer
  }

  func run(_ output: WhoKnowsMachine.Output) async -> WhoKnowsMachine.Event {
    switch output {
    case .read(let request):
      do throws(TransportError) {
        return .read(try await fetch(), request: request)
      } catch {
        return .readFailed(request: request)
      }
    case .answer(let request):
      do throws(TransportError) {
        return .answered(question: request.question, try await answer(request))
      } catch {
        return .answerFailed(question: request.question, WhoKnowsMachine.Failure(error))
      }
    }
  }
}

public typealias WhoKnowsStore = Store<WhoKnowsMachine>

extension WhoKnowsStore {
  /// Without a client or a viewer the account has no partner, and the round is unpaired.
  public static func whoKnows(_ client: WhoKnowsClient?, viewer: UserId?) -> WhoKnowsStore {
    WhoKnowsStore(initial: .initial(viewer: client == nil ? nil : viewer)) { output in
      await client?.run(output)
    }
  }
}
