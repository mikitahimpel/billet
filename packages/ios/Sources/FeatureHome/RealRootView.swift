import DesignSystem
import FeatureInbox
import FeatureOnboarding
import FeaturePairing
import FeatureSettings
import SwiftUI

/// The app when `BackendMode` is `real`: sign in, pair, then the paired screens.
public struct RealRootView: View {
  @State private var model: RealAppModel

  public init(model: RealAppModel) {
    _model = State(initialValue: model)
    try? BilletFonts.register()
  }

  public var body: some View {
    Group {
      switch model.stage {
      case .signedOut:
        OnboardingView(model: model.signIn) { model.signedIn() }
      case .unpaired:
        PairingFlowView(model: model.pairing) { model.paired() }
      case .paired:
        RealPairedView(model: model)
      }
    }
    .preferredColorScheme(.dark)
    .tint(Palette.gold.color)
    .calmAnimation(value: model.stage)
  }
}

/// The screens of a paired account: the notes and the account settings.
struct RealPairedView: View {
  let model: RealAppModel

  var body: some View {
    TabView {
      Tab("Notes", systemImage: "tray") {
        HistoryView(model: model.history())
      }
      Tab("Settings", systemImage: "gearshape") {
        AccountSettingsView(model: model.account()) { model.finished($0) }
      }
    }
  }
}
