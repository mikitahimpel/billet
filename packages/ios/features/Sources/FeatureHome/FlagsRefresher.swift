import Transport
import WidgetBridge
import Wire

/// Asks the server which test variants this pair is in and keeps the answer for offline use.
///
/// The answer replaces what was held, so an experiment the server stops listing falls away. A failed
/// request changes nothing: the app keeps the last answer, or its own defaults when it has none.
@MainActor
struct FlagsRefresher {
  let api: APIClient
  let labs: WidgetFeaturesModel

  /// Returns the service status the answer carried, if it carried one.
  @discardableResult
  func refresh() async -> AppStatus? {
    guard let response = try? await api.flags() else { return nil }
    // One entry per key; if the server repeated one, the first wins.
    let assignments = Dictionary(
      response.flags.map { ($0.key, $0.variant) }, uniquingKeysWith: { first, _ in first })
    labs.setRemote(RemoteFlags(assignments: assignments))
    return response.status
  }

  /// Forgets the pair's variants, for when the account leaves its pair or signs out: they belong
  /// to the pair, not to the phone.
  func forget() {
    labs.setRemote(RemoteFlags())
  }
}
