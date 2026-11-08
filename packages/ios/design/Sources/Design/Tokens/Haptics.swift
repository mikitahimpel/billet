import Foundation
import SwiftUI

/// Preferences kept in UserDefaults; only this phone's, never shared with the widgets.
public enum AppSettings {
  public static let hapticsKey = "haptics"

  public static var haptics: Bool {
    UserDefaults.standard.object(forKey: hapticsKey) as? Bool ?? true
  }
}

extension View {
  /// Haptic feedback, unless it is switched off in Settings.
  public func haptic(_ feedback: SensoryFeedback, trigger: some Equatable) -> some View {
    sensoryFeedback(feedback, trigger: trigger) { _, _ in AppSettings.haptics }
  }
}

/// The app's haptic vocabulary: one name per moment, so screens never pick a raw feedback style.
public enum Haptic: Sendable {
  /// A button was tapped.
  case tap
  /// The screen changed step.
  case step
  /// Something worked out: a pairing, a save.
  case confirmed
  /// Something was refused: a code that didn't work.
  case rejected

  var feedback: SensoryFeedback {
    switch self {
    case .tap: .impact(weight: .light)
    case .step: .selection
    case .confirmed: .success
    case .rejected: .error
    }
  }
}

extension View {
  /// A haptic from the vocabulary when `trigger` changes.
  public func haptic(_ haptic: Haptic, trigger: some Equatable) -> some View {
    self.haptic(haptic.feedback, trigger: trigger)
  }
}
