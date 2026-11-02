import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// What a window view is drawn from at one moment, on top of the room layer's own state.
public struct WindowViewState: Equatable, Sendable {
  /// The view, its weather and the hour it is lit for.
  public var view: WindowView
  public var weather: ViewWeather
  public var hour: ViewHour
  /// Seconds since the room started opening, for lights that stutter on with it.
  public var time: Double
  /// Wall-clock seconds, for the view's small life, so it never restarts with the room.
  public var now: Double
  /// The window's opening in the view's points, as the camera sees it now (four corners).
  public var window: [CGPoint]
  /// The same opening seen from the camera's home, which the view's planes are laid out on.
  public var home: [CGPoint]
  /// False while the room's own lamp is off, so the glass reflects less.
  public var lampOn: Bool

  public init(
    view: WindowView, weather: ViewWeather, hour: ViewHour, time: Double, now: Double,
    window: [CGPoint], home: [CGPoint], lampOn: Bool
  ) {
    self.view = view
    self.weather = weather
    self.hour = hour
    self.time = time
    self.now = now
    self.window = window
    self.home = home
    self.lampOn = lampOn
  }
}

/// Art for a window view, filling the scene behind the room. Return `nil` to keep the native
/// drawing of that view; a Rive file plugs in here one view at a time.
@MainActor
public protocol WindowViewArt {
  func view(_ view: WindowView, state: WindowViewState) -> AnyView?
}

extension EnvironmentValues {
  /// What a styled room's window looks out on, and in what weather and light.
  @Entry public var petSceneWindowView: WindowViewChoice = .standard
  /// Art that replaces some window views. `nil` keeps every native view.
  @Entry public var petSceneViewArt: (any WindowViewArt)? = nil
}
