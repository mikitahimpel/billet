import Foundation

/// One thing a partner did in a case, as the room keeps it: ids and a time, never text.
public struct CaseMark: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    /// `ref` is a beat id, or `Episode.endingRef` once the ending has been watched.
    case found
    /// `ref` is a suspect id.
    case named
  }

  public let episode: String
  public let kind: Kind
  public let ref: String
  public let at: Date

  public init(episode: String, kind: Kind, ref: String, at: Date) {
    self.episode = episode
    self.kind = kind
    self.ref = ref
    self.at = at
  }
}
