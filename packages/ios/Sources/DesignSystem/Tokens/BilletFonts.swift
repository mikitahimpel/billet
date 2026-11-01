import CoreText
import Foundation

public enum FontRegistrationError: Error, Equatable {
  case missing(String)
  case rejected(String)
}

/// Loads the bundled faces into the process. Call once at each process's entry point: the app, and
/// each extension that shows type.
public enum BilletFonts {
  public static let groteskFamily = "Schibsted Grotesk"
  public static let monoFamily = "DM Mono"

  public static func register() throws(FontRegistrationError) {
    for name in ["SchibstedGrotesk-Variable", "DMMono-Medium"] {
      guard
        let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
      else { throw .missing(name) }
      var error: Unmanaged<CFError>?
      if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
        let code = error.map { CFErrorGetCode($0.takeRetainedValue()) }
        if code != CTFontManagerError.alreadyRegistered.rawValue { throw .rejected(name) }
      }
    }
  }
}
