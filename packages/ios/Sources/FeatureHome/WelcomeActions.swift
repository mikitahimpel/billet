import DesignSystem
import SwiftUI

/// The first-launch choices over the cinematic: make a pair, join one with a code, or try billet
/// alone with the scripted partner.
struct WelcomeActions: View {
  let onCreate: () -> Void
  let onEnterCode: () -> Void
  let onTryAlone: () -> Void

  var body: some View {
    GlassGroup {
      VStack(spacing: Spacing.small) {
        BilletButton("Create pair", rank: .primary, action: onCreate)
        BilletButton("Enter code", rank: .secondary, action: onEnterCode)
        BilletButton("Try alone with a fake partner", rank: .secondary, action: onTryAlone)
      }
    }
  }
}
