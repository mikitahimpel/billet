import AppIntents
import Delivery
import Foundation
import Pet

#if canImport(WidgetKit)
  import WidgetKit
#endif

extension ActionSurface: AppEnum {
  public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Where"
  public static let caseDisplayRepresentations: [ActionSurface: DisplayRepresentation] = [
    .home: "Home Screen", .lockScreen: "Lock Screen", .control: "Control",
    .liveActivity: "Live Activity", .shortcut: "Shortcut",
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

/// The note widget's one button: a pet or a treat, whichever the cat needs. It runs without
/// opening the app, tells the room straight away, and hands the care to the app's queue when the
/// room cannot be reached.
public enum CatCareSubmission {
  @discardableResult
  public static func submit(now: Date = .now, calendar: Calendar = .current) async -> Bool {
    let snapshots = WidgetSnapshotStore.appGroup()
    let records = CatCareStore.appGroup()
    let snapshot = snapshots?.load()
    let decision = CatCareRequest.decide(
      snapshot: snapshot, last: records?.load(), now: now, calendar: calendar)
    guard case .success(let care) = decision, let snapshot, let records,
      (try? records.save(CatCareRecord(care: care, at: now))) != nil
    else { return false }

    let current = snapshot.current(now: now, calendar: calendar)
    let plays = care.plays(treat: current.treat).map { (id: UUID(), kind: $0) }
    let room = DemoRoom.saved()
    try? snapshots?.save(
      CatCareRequest.applied(
        plays, by: room?.device, to: snapshot, now: now, calendar: calendar))
    reload()

    let at = TreatDay.timestamp(for: now, calendar: calendar)
    let frames = plays.map { RoomPlay(id: $0.id, kind: $0.kind.rawValue, at: at) }
    if let room, let host = DemoRoom.host(), await room.post(frames, host: host) {
      return true
    }
    let action = WidgetAction(
      kind: care.action, at: now, day: TreatDay.key(for: now, calendar: calendar))
    try? ActionQueue.appGroup()?.enqueue(action)
    reload()
    return true
  }

  private static func reload() {
    #if canImport(WidgetKit)
      WidgetCenter.shared.reloadAllTimelines()
    #endif
  }
}

public struct CareForCatIntent: AppIntent {
  public static let title: LocalizedStringResource = "Care for the cat"
  public static let description = IntentDescription(
    "Pets the cat, or gives it a treat when it is hungry. Your partner sees it.")
  public static let isDiscoverable = false

  public init() {}

  public func perform() async throws -> some IntentResult {
    await CatCareSubmission.submit()
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

#if os(iOS)
  import ActivityKit

  /// The heart button of the cat's trip. It queues the heart like any widget button and marks the
  /// activity, so the Lock Screen shows it was asked for.
  public struct HeartTripIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Send a heart"
    public static let isDiscoverable = false

    public init() {}

    public func perform() async throws -> some IntentResult {
      guard ActionSubmission.submit(.heart, at: .liveActivity) else { return .result() }
      for activity in Activity<CatTripAttributes>.activities {
        let content = CatTrip.hearted(activity.content.state)
        await activity.update(ActivityContent(state: content, staleDate: nil))
      }
      return .result()
    }
  }
#endif
