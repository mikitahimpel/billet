import Foundation
import WidgetBridge

#if os(iOS)
  import ActivityKit
#endif

/// Starts the "cat is on its way" Live Activity when a note sets off, and ends it when the note
/// is hung. It starts the activity locally; a server start would use the same content.
@MainActor
final class CatTripController {
  /// What starting, updating and ending an activity does, so tests can stand in for ActivityKit.
  struct Backend {
    var start: @MainActor (_ catName: String?, _ content: CatTrip.Content) async -> Void
    var update: @MainActor (_ content: CatTrip.Content) async -> Void
    var end: @MainActor (_ content: CatTrip.Content, _ lingering: TimeInterval) async -> Void
  }

  private let backend: Backend
  private let features: @Sendable () -> WidgetFeatures
  private(set) var current: CatTrip.Content?

  init(backend: Backend, features: @escaping @Sendable () -> WidgetFeatures) {
    self.backend = backend
    self.features = features
  }

  static func live() -> CatTripController {
    CatTripController(
      backend: .activityKit,
      features: { WidgetFeaturesStore.appGroup()?.load() ?? WidgetFeatures() })
  }

  /// A note set off. Does nothing when the feature is off. A trip still running is ended first.
  func noteOnItsWay(catName: String?, reveal: Duration, now: Date = .now) async {
    guard features().isOn(.liveActivity) else { return }
    if let previous = current { await backend.end(previous, 0) }
    let content = CatTrip.begin(at: now, duration: CatTrip.expectedDuration(reveal: reveal))
    current = content
    await backend.start(catName, content)
    // A scene that never reports the note hung must not leave the activity up for good.
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(content.arrivesAt.timeIntervalSince(now) + 30))
      guard let self, self.current == content else { return }
      await self.cancel()
    }
  }

  /// The note is on the wall.
  func noteHung(now: Date = .now) async {
    guard let trip = current else { return }
    current = nil
    await backend.end(CatTrip.hung(trip, at: now), CatTrip.lingerAfterHung)
  }

  /// The trip is abandoned without a hang, for example when the pair is logged out.
  func cancel() async {
    guard let trip = current else { return }
    current = nil
    await backend.end(trip, 0)
  }
}

extension CatTripController.Backend {
  #if os(iOS)
    static let activityKit = CatTripController.Backend(
      start: { catName, content in
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Local start only. Asking for push updates later means passing `pushType: .token` here
        // and sending the token it reports to the backend; see docs/live-activity.md.
        _ = try? Activity.request(
          attributes: CatTripAttributes(catName: catName),
          content: ActivityContent(
            state: content, staleDate: content.arrivesAt.addingTimeInterval(60)),
          pushType: nil)
      },
      update: { content in
        for activity in Activity<CatTripAttributes>.activities {
          await activity.update(ActivityContent(state: content, staleDate: nil))
        }
      },
      end: { content, lingering in
        for activity in Activity<CatTripAttributes>.activities {
          await activity.end(
            ActivityContent(state: content, staleDate: nil),
            dismissalPolicy: lingering > 0 ? .after(.now.addingTimeInterval(lingering)) : .immediate
          )
        }
      })
  #else
    static let activityKit = CatTripController.Backend(
      start: { _, _ in }, update: { _ in }, end: { _, _ in })
  #endif
}
