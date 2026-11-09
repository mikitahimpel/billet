import BilletKit
import Foundation
import Transport
import Wire

/// The pair's Draw & guess riddles in their room. Every riddle call answers the riddle as this user
/// sees it after it.
public struct DrawGuessClient: Sendable {
  public var fetch: @Sendable () async throws(TransportError) -> RiddlesResponse
  /// The drawing's PNG to the media store, before the riddle that names it.
  public var upload: @Sendable (Data) async throws(TransportError) -> MediaKey
  public var send: @Sendable (SendRiddleRequest) async throws(TransportError) -> Riddle
  public var guess:
    @Sendable (RiddleId, IdempotencyKey, String) async throws(TransportError) -> GuessRiddleResponse
  public var hint: @Sendable (RiddleId) async throws(TransportError) -> Riddle
  public var giveUp: @Sendable (RiddleId) async throws(TransportError) -> Riddle

  public init(
    fetch: @escaping @Sendable () async throws(TransportError) -> RiddlesResponse,
    upload: @escaping @Sendable (Data) async throws(TransportError) -> MediaKey,
    send: @escaping @Sendable (SendRiddleRequest) async throws(TransportError) -> Riddle,
    guess:
      @escaping @Sendable (RiddleId, IdempotencyKey, String) async throws(TransportError) ->
      GuessRiddleResponse,
    hint: @escaping @Sendable (RiddleId) async throws(TransportError) -> Riddle,
    giveUp: @escaping @Sendable (RiddleId) async throws(TransportError) -> Riddle
  ) {
    self.fetch = fetch
    self.upload = upload
    self.send = send
    self.guess = guess
    self.hint = hint
    self.giveUp = giveUp
  }

  func run(_ output: DrawGuessMachine.Output) async -> DrawGuessMachine.Event {
    typealias Failure = DrawGuessMachine.Failure
    switch output {
    case .read(let request):
      do throws(TransportError) {
        return .read(try await fetch(), request: request)
      } catch {
        return .readFailed(request: request)
      }
    case .guess(let id, let key, let word):
      do throws(TransportError) {
        return .guessed(id, try await guess(id, key, word))
      } catch {
        return .guessFailed(id, Failure(error))
      }
    case .hint(let id):
      do throws(TransportError) {
        return .hinted(try await hint(id))
      } catch {
        return .hintFailed(id, Failure(error))
      }
    case .giveUp(let id):
      do throws(TransportError) {
        return .gaveUp(try await giveUp(id))
      } catch {
        return .giveUpFailed(id, Failure(error))
      }
    case .send(let upload):
      do throws(TransportError) {
        let image = try await self.upload(upload.png)
        let request = SendRiddleRequest(
          id: upload.id, word: upload.word, compact: upload.compact, image: image)
        return .sent(try await send(request))
      } catch {
        return .sendFailed(upload.id, Failure(error))
      }
    }
  }
}

public typealias DrawGuessStore = Store<DrawGuessMachine>

extension DrawGuessStore {
  /// Without a client or a viewer the account has no partner, and the game is unpaired.
  public static func drawGuess(_ client: DrawGuessClient?, viewer: UserId?) -> DrawGuessStore {
    DrawGuessStore(initial: .initial(viewer: client == nil ? nil : viewer)) { output in
      await client?.run(output)
    }
  }
}
