/// Whether a pair has the secret-life mysteries: the `story` experiment. Off for everyone the server says nothing
/// to, and for any variant this build lacks.
public enum StoryVariant: String, CaseIterable, Sendable, RemoteChoice {
  case off
  case on

  public static func resolved(remote: RemoteFlags) -> StoryVariant {
    remote.choice(of: Experiments.story) ?? .off
  }

  public var isOn: Bool { self == .on }
}
