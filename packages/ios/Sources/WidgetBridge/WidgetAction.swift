import Foundation
import Pet

/// Something done from a widget, a control or a Live Activity that the app must carry out.
public enum WidgetActionKind: String, Codable, CaseIterable, Sendable {
  case treat
  case pet
  case heart
  case openCanvas

  /// How long the action stays worth doing. A pet only matters now; a treat or a heart can wait
  /// for the next time the app is open.
  var lifetime: TimeInterval {
    switch self {
    case .pet: 10 * 60
    case .openCanvas: 2 * 60
    case .treat, .heart: 48 * 60 * 60
    }
  }
}

public struct WidgetAction: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let kind: WidgetActionKind
  public let at: Date
  /// The calendar day a treat is for, in the phone's calendar when it was asked for.
  public let day: String
  /// The note a heart answers.
  public let note: UUID?

  public init(
    id: UUID = UUID(), kind: WidgetActionKind, at: Date, day: String, note: UUID? = nil
  ) {
    self.id = id
    self.kind = kind
    self.at = at
    self.day = day
    self.note = note
  }

  public func isStale(at now: Date) -> Bool {
    now.timeIntervalSince(at) > kind.lifetime
  }
}

/// Actions waiting for the app, one file each so the widget and the app never rewrite the same file.
public struct ActionQueue: Sendable {
  private static let directoryName = "WidgetActions"

  private let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  public static func appGroup() -> ActionQueue? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: "group.com.mikitahimpel.billet")
      .map {
        ActionQueue(directory: $0.appending(path: directoryName, directoryHint: .isDirectory))
      }
  }

  public func enqueue(_ action: WidgetAction) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let name = "\(Int(action.at.timeIntervalSince1970 * 1000))-\(action.id.uuidString).json"
    try JSONEncoder().encode(action).write(
      to: directory.appending(path: name, directoryHint: .notDirectory), options: .atomic)
  }

  /// The actions still worth doing, oldest first. Stale and unreadable files are deleted.
  public func pending(at now: Date) -> [WidgetAction] {
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)) ?? []
    var live: [WidgetAction] = []
    for file in files where file.pathExtension == "json" {
      if let action = (try? Data(contentsOf: file)).flatMap({
        try? JSONDecoder().decode(WidgetAction.self, from: $0)
      }), !action.isStale(at: now) {
        live.append(action)
      } else {
        try? FileManager.default.removeItem(at: file)
      }
    }
    return live.sorted { ($0.at, $0.id.uuidString) < ($1.at, $1.id.uuidString) }
  }

  public func remove(_ action: WidgetAction) {
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)) ?? []
    for file in files where file.lastPathComponent.contains(action.id.uuidString) {
      try? FileManager.default.removeItem(at: file)
    }
  }

  public func removeAll() {
    try? FileManager.default.removeItem(at: directory)
  }
}

/// Where an action was taken. Each place has its own switch.
public enum ActionSurface: String, Codable, CaseIterable, Sendable {
  case home
  case lockScreen
  case control
  case liveActivity
  case shortcut
}

/// Decides whether an action from a widget is queued, and says why when it is not.
public enum WidgetActionRequest {
  public enum Refusal: Error, Equatable, Sendable {
    /// The feature is switched off in Settings.
    case off
    /// There is no note from the partner to answer.
    case noNote
    /// The same thing is already done or already waiting.
    case duplicate
  }

  /// The most pets that wait at once, so a restless thumb cannot pile up a burst.
  public static let petLimit = 5

  /// The flags that must all be on for `kind` taken at `surface`.
  public static func required(_ kind: WidgetActionKind, at surface: ActionSurface)
    -> [WidgetFeature]
  {
    switch surface {
    case .home, .lockScreen:
      let button: WidgetFeature? =
        switch kind {
        case .treat: .buttonTreat
        case .pet: .buttonPet
        case .heart: .buttonHeart
        case .openCanvas: nil
        }
      return [button].compactMap { $0 }
    case .control, .liveActivity, .shortcut:
      return []
    }
  }

  public static func decide(
    _ kind: WidgetActionKind, at surface: ActionSurface, features: WidgetFeatures,
    snapshot: WidgetSnapshot?, pending: [WidgetAction], now: Date, calendar: Calendar
  ) -> Result<WidgetAction, Refusal> {
    guard required(kind, at: surface).allSatisfy(features.isOn) else { return .failure(.off) }
    let current = snapshot?.current(now: now, calendar: calendar)
    let day = TreatDay.key(for: now, calendar: calendar)
    let waiting = pending.filter { $0.kind == kind }
    switch kind {
    case .treat:
      if let current, current.treat == .waitingOnPartner || current.treat == .fed {
        return .failure(.duplicate)
      }
      if waiting.contains(where: { $0.day == day }) { return .failure(.duplicate) }
      return .success(WidgetAction(kind: kind, at: now, day: day))
    case .pet:
      if waiting.count >= petLimit { return .failure(.duplicate) }
      return .success(WidgetAction(kind: kind, at: now, day: day))
    case .heart:
      guard let note = current?.latestReceivedNote else { return .failure(.noNote) }
      if waiting.contains(where: { $0.note == note }) { return .failure(.duplicate) }
      return .success(WidgetAction(kind: kind, at: now, day: day, note: note))
    case .openCanvas:
      return .success(WidgetAction(kind: kind, at: now, day: day))
    }
  }
}
