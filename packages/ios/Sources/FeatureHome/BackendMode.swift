import Foundation

/// Which backend the app talks to, chosen by the build.
///
/// `demo` is the default and the only thing a build gets without asking: the demo room, the fake
/// partner and none of the real client. `real` needs an `https` (or local `http`) base URL.
public enum BackendMode: Equatable, Sendable {
  case demo
  case real(baseURL: URL)

  /// Reads the `BilletBackend` and `BilletAPIBaseURL` Info.plist values. Anything that is not
  /// exactly `real` with a usable URL is `demo`, so a typo cannot switch a build to the real client.
  public init(backend: String?, baseURL: String?) {
    guard backend == "real", let baseURL, let url = URL(string: baseURL),
      let scheme = url.scheme, ["https", "http"].contains(scheme), url.host() != nil
    else {
      self = .demo
      return
    }
    self = .real(baseURL: url)
  }

  public init(info: [String: Any]?) {
    self.init(
      backend: info?["BilletBackend"] as? String, baseURL: info?["BilletAPIBaseURL"] as? String)
  }
}
