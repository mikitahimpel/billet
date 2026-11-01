import AppIntents
import WidgetBridge

/// Makes the intents the widget runs known to the app too, so Shortcuts and the system can find
/// them in the app's own metadata.
struct BilletIntents: AppIntentsPackage {
  static var includedPackages: [any AppIntentsPackage.Type] { [WidgetBridgeIntents.self] }
}
