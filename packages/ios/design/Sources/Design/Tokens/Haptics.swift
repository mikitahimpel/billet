import Foundation
import SwiftUI

/// Only this phone's, never shared with the widgets.
public enum AppSettings {
  public static let hapticsKey = "haptics"

  public static var haptics: Bool {
    UserDefaults.standard.object(forKey: hapticsKey) as? Bool ?? true
  }
}

extension View {
  public func haptic(_ feedback: SensoryFeedback, trigger: some Equatable) -> some View {
    sensoryFeedback(feedback, trigger: trigger) { _, _ in AppSettings.haptics }
  }
}

/// One name per moment, so screens never pick a raw feedback style.
public enum Haptic: Sendable {
  case tap
  case step
  case confirmed
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
  public func haptic(_ haptic: Haptic, trigger: some Equatable) -> some View {
    self.haptic(haptic.feedback, trigger: trigger)
  }
}
