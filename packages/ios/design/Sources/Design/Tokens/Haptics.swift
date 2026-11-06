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
