import AppIntents
import Foundation

#if canImport(WidgetKit)
  import WidgetKit
#endif

extension ActionSurface: AppEnum {
  public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Where"
  public static let caseDisplayRepresentations: [ActionSurface: DisplayRepresentation] = [
    .home: "Home Screen", .lockScreen: "Lock Screen", .control: "Control",
    .liveActivity: "Live Activity",
  ]
}

/// What an intent does with a request: queue it for the app, or refuse. Nothing here reaches the
/// partner. Widgets and controls run without the room connection, so the app sends the action
/// the next time it is open and connected.
public enum ActionSubmission {
  @discardableResult
  public static func submit(_ kind: WidgetActionKind, at surface: ActionSurface) -> Bool {
    let now = Date.now
    let features = WidgetFeaturesStore.appGroup()?.load() ?? WidgetFeatures()
    guard let queue = ActionQueue.appGroup() else { return false }
    let decision = WidgetActionRequest.decide(
      kind, at: surface, features: features, snapshot: WidgetSnapshotStore.appGroup()?.load(),
      pending: queue.pending(at: now), now: now, calendar: Calendar.current)
    guard case .success(let action) = decision, (try? queue.enqueue(action)) != nil else {
      return false
    }
    #if canImport(WidgetKit)
      WidgetCenter.shared.reloadAllTimelines()
    #endif
    return true
  }
}

public struct GiveTreatIntent: AppIntent {
  public static let title: LocalizedStringResource = "Give today's treat"
  public static let description = IntentDescription("Gives the cat today's treat from you.")
  public static let isDiscoverable = false

  @Parameter(title: "Where", default: .home) public var surface: ActionSurface

  public init() {}
  public init(surface: ActionSurface) { self.surface = surface }

  public func perform() async throws -> some IntentResult {
    ActionSubmission.submit(.treat, at: surface)
    return .result()
  }
}

public struct PetCatIntent: AppIntent {
  public static let title: LocalizedStringResource = "Pet the cat"
  public static let description = IntentDescription("Pets the cat; your partner's phone feels it.")
  public static let isDiscoverable = false

  @Parameter(title: "Where", default: .home) public var surface: ActionSurface

  public init() {}
  public init(surface: ActionSurface) { self.surface = surface }

  public func perform() async throws -> some IntentResult {
    ActionSubmission.submit(.pet, at: surface)
    return .result()
  }
}

public struct SendHeartIntent: AppIntent {
  public static let title: LocalizedStringResource = "Send a heart"
  public static let description = IntentDescription("Sends a heart on your partner's newest note.")
  public static let isDiscoverable = false

  @Parameter(title: "Where", default: .home) public var surface: ActionSurface

  public init() {}
  public init(surface: ActionSurface) { self.surface = surface }

  public func perform() async throws -> some IntentResult {
    ActionSubmission.submit(.heart, at: surface)
    return .result()
  }
}

public struct OpenCanvasIntent: AppIntent {
  public static let title: LocalizedStringResource = "Draw a note"
  public static let description = IntentDescription("Opens billet on the canvas.")
  public static let openAppWhenRun = true
  public static let isDiscoverable = false

  @Parameter(title: "Where", default: .control) public var surface: ActionSurface

  public init() {}
  public init(surface: ActionSurface) { self.surface = surface }

  public func perform() async throws -> some IntentResult {
    ActionSubmission.submit(.openCanvas, at: surface)
    return .result()
  }
}

/// Lets the app and the widget both see the intents defined here.
public struct WidgetBridgeIntents: AppIntentsPackage {}
