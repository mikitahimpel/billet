import Foundation
import PetScene
import SwiftUI

/// When a flat layer over a room redraws: every frame while the room opens or warms after a note
/// lands, then only as often as what still moves in it needs, or not at all. A layer still redraws
/// whenever the camera moves, since it reads where things are from the room's screen.
struct RoomLayerSchedule: TimelineSchedule {
  /// Until when everything in the layer moves: the end of the opening or of the warmth.
  var busyUntil: Date
  /// How often the layer changes once the room is settled, or `nil` when it then holds still.
  var steady: TimeInterval?
  var isPaused: Bool

  /// How often a layer redraws while everything in it moves, as fast as the room is drawn. Set by
  /// ``FramePace``.
  nonisolated(unsafe) static var busy: TimeInterval = 1 / 30

  struct Entries: Sequence, IteratorProtocol {
    var upcoming: Date?
    let busyUntil: Date
    let steady: TimeInterval?

    mutating func next() -> Date? {
      guard let date = upcoming else { return nil }
      if date < busyUntil {
        upcoming = date.addingTimeInterval(RoomLayerSchedule.busy)
      } else {
        upcoming = steady.map { date.addingTimeInterval($0) }
      }
      return date
    }
  }

  func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
    guard !isPaused else {
      return Entries(upcoming: startDate, busyUntil: .distantPast, steady: nil)
    }
    let steady = mode == .lowFrequency ? steady.map { max($0, 1) } : steady
    return Entries(upcoming: startDate, busyUntil: busyUntil, steady: steady)
  }
}

extension GenzRoomScreen {
  /// Until when a styled room's layers move every frame: its opening, and the warmth after a
  /// note lands, each with a moment's grace.
  var busyUntil: Date {
    let opened = openedAt.map { $0.addingTimeInterval(GenzOpening.length + 0.5) }
    let warm = landedAt.map { $0.addingTimeInterval(GenzOpening.warmthLength + 0.5) }
    let ends = [opened, warm].compactMap { $0 }
    // Still dark and loading: keep drawing until the opening starts.
    guard openedAt != nil else { return .distantFuture }
    return ends.max() ?? .distantPast
  }
}

extension RoomLayerSlot {
  /// How often the layer changes once the room has opened, or `nil` when it holds still.
  var steadyInterval: TimeInterval? {
    switch self {
    // The view outside: cars, planes, weather and its own small life. Each redraw paints the whole
    // view, sky, planes, haze and glass, so it costs more than any other layer; its life is small
    // and far off, and 15 a second is smooth enough for it. A moving camera redraws it every frame.
    case .windowNight: 1 / 15
    case .windowBloom, .windowBacklight, .windowDim: nil
    }
  }

  /// Whether the native layer moves with the camera. The dims fill the view whatever it sees.
  var nativeFollowsCamera: Bool {
    switch self {
    case .windowDim: false
    case .windowNight, .windowBloom, .windowBacklight: true
    }
  }
}

/// Where a drag or a pinch was last frame. Held by reference, so following a finger does not
/// redraw the view that owns it.
@MainActor
final class GestureTrack {
  var drag = CGSize.zero
  var pinch: CGFloat = 1
}

/// The preset's haze, clear through the window as the camera sees it now. Its own view, so the
/// camera moving redraws only the haze and not the room's whole view.
struct RoomHaze: View {
  let look: LightingLook
  let screen: GenzRoomScreen

  var body: some View {
    GlowHaze(look: look, window: screen.window)
  }
}

/// Puts the cat's place on screen in ``PetSceneCatAnchorKey``. Its own view, for the same reason.
struct RoomCatAnchor: View {
  let screen: GenzRoomScreen

  var body: some View {
    Color.clear
      .anchorPreference(key: PetSceneCatAnchorKey.self, value: .point(screen.cat ?? .zero)) {
        screen.cat == nil ? nil : $0
      }
      .allowsHitTesting(false)
  }
}
