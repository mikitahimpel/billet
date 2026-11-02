import DesignSystem
import FeatureOnboarding
import FeaturePairing
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
        PairedPlaceholderView()
      }
    }
    .preferredColorScheme(.dark)
    .tint(Palette.gold.color)
    .calmAnimation(value: model.stage)
  }
}

/// Stands in for the inbox and settings screens until they are connected.
struct PairedPlaceholderView: View {
  var body: some View {
    ZStack {
      EveningBackground()
      Text("You're paired.")
        .billetType(.title)
        .foregroundStyle(Palette.paper.color)
    }
  }
}
