import Foundation

#if os(iOS) && canImport(WidgetKit)
  import WidgetKit
#endif

/// Whether this phone has a billet widget on a Home Screen, the Lock Screen or StandBy.
enum WidgetPresence {
  @MainActor
  static func isInstalled() async -> Bool {
    #if os(iOS) && canImport(WidgetKit)
      guard let configurations = try? await WidgetCenter.shared.currentConfigurations() else {
        return false
      }
      return !configurations.isEmpty
    #else
      return false
    #endif
  }
}
