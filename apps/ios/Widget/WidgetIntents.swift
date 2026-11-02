import AppIntents
import WidgetBridge

/// Makes the intents defined in WidgetBridge part of this extension's own metadata.
struct WidgetIntents: AppIntentsPackage {
  static var includedPackages: [any AppIntentsPackage.Type] { [WidgetBridgeIntents.self] }
}
