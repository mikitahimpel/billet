import SwiftUI

#if canImport(UIKit)
  /// What onboarding draws that only the app can: the 3D hero cat and the backdrops, which share their
  /// drawing with the room.
  public protocol OnboardingScenery {
    func heroBackdrop() -> AnyView
    func warmBackdrop() -> AnyView
    /// Mochi on her stage; `time` is seconds since the welcome appeared.
    func heroStage(coat: CatCoat, time: TimeInterval, pokedAt: TimeInterval?, moving: Bool)
      -> AnyView
  }
#endif
