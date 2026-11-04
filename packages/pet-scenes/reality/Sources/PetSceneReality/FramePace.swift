import Foundation
import Observation
import PetScene
import RealityKit

/// How often the scenes may draw. A phone that draws a room at the display's rate while nothing in
/// it changes runs hot for nothing, and once hot it slows down and stutters. So a scene draws at
/// most 30 times a second, a room 15 once it is still and nobody touches it, and every scene 20 at
/// most while the device is hot, when the room also leaves out its haze. Under a sheet a room draws
/// 10 times a second.
@MainActor @Observable
final class FramePace {
  static let shared = FramePace()

  /// While something moves: the camera, the cat, a finger, the opening.
  nonisolated static let moving: Float = 30
  /// While a sheet covers the room.
  nonisolated static let covered: Float = 10
  /// While the room holds still and nobody touches it.
  nonisolated static let still: Float = 15
  /// The most while the device is hot.
  nonisolated static let hot: Float = 20
  /// How long after the last touch or movement a room counts as still, in seconds.
  nonisolated static let stillAfter: TimeInterval = 3

  /// Whether the device is hot enough that it would soon slow itself down.
  private(set) var isHot = false
  /// Off only in a measuring run's `frameCap` switch, to compare with drawing at the display's rate.
  private(set) var isCapped = true
  @ObservationIgnored private var observer: (any NSObjectProtocol)?

  private init() {
    isHot = Self.isHot(ProcessInfo.processInfo.thermalState)
    observer = NotificationCenter.default.addObserver(
      forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
    ) { _ in
      MainActor.assumeIsolated { FramePace.shared.thermalStateChanged() }
    }
  }

  nonisolated static func isHot(_ state: ProcessInfo.ThermalState) -> Bool {
    state == .serious || state == .critical
  }

  /// The frames a second for a scene, or nil for the display's own rate. Under a sheet it draws
  /// at the gentlest pace, whatever moves in it.
  func rate(isStill: Bool, isCovered: Bool = false) -> Float? {
    guard isCapped else { return nil }
    let rate = isCovered ? Self.covered : isStill ? Self.still : Self.moving
    return isHot ? min(rate, Self.hot) : rate
  }

  /// How often the flat layers over a room redraw while everything in them moves.
  var busyInterval: TimeInterval { isCapped ? 1 / Double(isHot ? Self.hot : Self.moving) : 1 / 60 }

  func setCapped(_ isCapped: Bool) {
    self.isCapped = isCapped
    RoomLayerSchedule.busy = busyInterval
  }

  private func thermalStateChanged() {
    let hot = Self.isHot(ProcessInfo.processInfo.thermalState)
    guard hot != isHot else { return }
    isHot = hot
    RoomLayerSchedule.busy = busyInterval
  }
}

/// Counts RealityKit's scene updates in a measuring run, so a run can tell how often the room is
/// really drawn, not only how often the display could have shown it.
struct PerfRenderSystem: System {
  @MainActor private static var isRegistered = false

  init(scene: RealityKit.Scene) {}

  @MainActor static func registerOnce() {
    guard ScenePerf.isOn, !isRegistered else { return }
    isRegistered = true
    registerSystem()
  }

  func update(context: SceneUpdateContext) {
    MainActor.assumeIsolated { ScenePerf.count("renders") }
  }
}
