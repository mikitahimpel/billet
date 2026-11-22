import Foundation
import StoryInterface
import Transport
import Wire

/// The pair's room, as the case needs it: read the marks, write one. A failure is `nil`; the machine keeps what it
/// had and the write can be sent again.
public struct StoryClient: Sendable {
  public var fetch: @Sendable () async -> CaseMachine.Marks?
  public var mark:
    @Sendable (_ episode: String, _ kind: CaseMark.Kind, _ ref: String) async -> CaseMachine.Marks?

  public init(
    fetch: @escaping @Sendable () async -> CaseMachine.Marks?,
    mark: @escaping @Sendable (String, CaseMark.Kind, String) async -> CaseMachine.Marks?
  ) {
    self.fetch = fetch
    self.mark = mark
  }

  public static let offline = StoryClient(fetch: { nil }, mark: { _, _, _ in nil })

  public static func live(_ api: APIClient) -> StoryClient {
    StoryClient(
      fetch: { try? await api.story().marks },
      mark: { episode, kind, ref in
        guard let id = StoryId(rawValue: episode), let refID = StoryId(rawValue: ref) else {
          return nil
        }
        let request = StoryMarkRequest(episode: id, kind: kind.wire, ref: refID)
        return try? await api.markStory(request).marks
      })
  }
}

extension CaseMark.Kind {
  var wire: StoryMarkKind {
    switch self {
    case .found: .found
    case .named: .named
    }
  }
}

extension StoryMark {
  var caseMark: CaseMark {
    let kind: CaseMark.Kind =
      switch self.kind {
      case .found: .found
      case .named: .named
      }
    return CaseMark(
      episode: episode.rawValue, kind: kind, ref: ref.rawValue,
      at: Date(timeIntervalSince1970: Double(at) / 1000))
  }
}

extension StoryResponse {
  var marks: CaseMachine.Marks {
    CaseMachine.Marks(mine: mine.map(\.caseMark), partner: partner.map(\.caseMark))
  }
}
