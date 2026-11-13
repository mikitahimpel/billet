import DrawInterface
import Foundation
import Persistence
import Transport
import Wire

/// Fetches unseen notes, saves the partner's newest drawing for the widgets, and registers APNs tokens.
@MainActor
public struct DrawingSync {
  let api: APIClient
  let accounts: AccountStore
  let defaults: UserDefaults
  /// Reloads the timelines of one widget kind.
  let reloadWidgets: @MainActor (String) -> Void

  public static let cursorKey = "drawings.lastSeq"

  public init(
    api: APIClient, accounts: AccountStore, defaults: UserDefaults,
    reloadWidgets: @escaping @MainActor (String) -> Void
  ) {
    self.api = api
    self.accounts = accounts
    self.defaults = defaults
    self.reloadWidgets = reloadWidgets
  }

  public func fetchLatest() async {
    let viewer = (try? accounts.load())?.record.userID
    var after = defaults.object(forKey: Self.cursorKey) as? Int
    var newest: LatestDrawing?
    while let page = try? await api.listNotes(after), let last = page.lastSeq {
      for entry in page.notes {
        if let drawing = LatestDrawing(entry.note, seq: entry.seq, viewer: viewer) {
          newest = drawing
        }
      }
      after = last
      defaults.set(last, forKey: Self.cursorKey)
    }
    save(newest)
  }

  /// A note that came over the socket while the app was open.
  public func received(_ note: Wire.Note, seq: Int) {
    save(LatestDrawing(note, seq: seq, viewer: (try? accounts.load())?.record.userID))
  }

  private func save(_ drawing: LatestDrawing?) {
    guard let drawing, drawing.saveIfNewer() else { return }
    LatestDrawing.widgetKinds.forEach(reloadWidgets)
  }

  /// Sends the server any APNs token it does not have yet: the alert token, the widgets' token and the Live
  /// Activity push-to-start token.
  public func registerPushTokens() async {
    let tokens = PushTokens.load()
    #if DEBUG
      let environment = ApnsEnvironment.sandbox
    #else
      let environment = ApnsEnvironment.production
    #endif
    if let alert = tokens.alert, alert != tokens.registeredAlert,
      (try? await api.registerPushToken(
        .init(kind: .alert, environment: environment, token: PushToken(alert)))) != nil
    {
      PushTokens.update { $0.registeredAlert = alert }
    }
    if let widget = tokens.widget, widget != tokens.registeredWidget,
      (try? await api.registerPushToken(
        .init(kind: .widget, environment: environment, token: PushToken(widget)))) != nil
    {
      PushTokens.update { $0.registeredWidget = widget }
    }
    if let start = tokens.liveActivity, start != tokens.registeredLiveActivity,
      (try? await api.registerPushToken(
        .init(
          kind: .liveactivity, environment: environment,
          token: PushToken(start)))) != nil
    {
      PushTokens.update { $0.registeredLiveActivity = start }
    }
  }
}
