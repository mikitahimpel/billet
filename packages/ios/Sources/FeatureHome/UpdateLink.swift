import Foundation

/// Where "Update billet" sends the user, chosen by the build.
public enum UpdateLink: Equatable, Sendable {
  /// The TestFlight app, which offers the newest build to a tester.
  case testFlight
  case url(URL)

  /// Reads a `BilletUpdateURL` value. Empty, missing or not an App Store, TestFlight or `https`
  /// link is TestFlight.
  public init(_ value: String?) {
    guard let value, let url = URL(string: value), let scheme = url.scheme,
      ["https", "itms-apps", "itms-beta"].contains(scheme)
    else {
      self = .testFlight
      return
    }
    self = .url(url)
  }

  /// Reads the `BilletUpdateURL` Info.plist value, which the `BILLET_UPDATE_URL` build setting
  /// fills.
  public init(info: [String: Any]?) {
    self.init(info?["BilletUpdateURL"] as? String)
  }

  public var url: URL? {
    switch self {
    case .testFlight: URL(string: "itms-beta://")
    case .url(let url): url
    }
  }
}
