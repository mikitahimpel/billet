import Foundation

#if os(iOS) && canImport(WidgetKit)
  import WidgetKit
#endif

/// The billet widgets this phone has on a Home Screen, the Lock Screen or StandBy.
enum WidgetPresence {
  /// The kind of each widget there, as the widget extension names it (`LatestNote`, `Pictures`).
  /// Empty when there are none or the system cannot say.
  @MainActor
  static func kinds() async -> Set<String> {
    #if os(iOS) && canImport(WidgetKit)
      guard let configurations = try? await WidgetCenter.shared.currentConfigurations() else {
        return []
      }
      return Set(configurations.map(\.kind))
    #else
      return []
    #endif
  }
}
