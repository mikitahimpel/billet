import Foundation

public enum PictureMode: String, CaseIterable, Sendable {
  case nudge
  case partnerDrawing
  case partnerWindow
  case streak
  case daysTogether
  case timeOfDay

  public var feature: WidgetFeature {
    switch self {
    case .nudge: .nudge
    case .partnerDrawing: .partnerDrawing
    case .partnerWindow: .partnerWindow
    case .streak: .streak
    case .daysTogether: .daysTogether
    case .timeOfDay: .timeOfDay
    }
  }
}

/// The part of the day, which sets the sky behind the house.
public enum DayPhase: String, CaseIterable, Sendable {
  case dawn
  case day
  case dusk
  case night

  public init(hour: Int) {
    switch hour {
    case 5..<8: self = .dawn
    case 8..<17: self = .day
    case 17..<21: self = .dusk
    default: self = .night
    }
  }

  public var title: String {
    switch self {
    case .dawn: "Morning"
    case .day: "Daytime"
    case .dusk: "Evening"
    case .night: "Night"
    }
  }
}

/// Which pictures a widget may show, and in what order over time.
public enum PicturePlan {
  /// How long each picture stays when the pictures take turns.
  public static let slot: TimeInterval = 15 * 60
  /// How long the plan covers before the widget asks again.
  public static let horizon: TimeInterval = 8 * 60 * 60
  /// Days without a drawing from this device before the nudge appears.
  public static let nudgeAfterDays = 2

  public struct Inputs: Sendable {
    public var features: WidgetFeatures
    public var snapshot: WidgetSnapshot?
    public var hasDrawing: Bool
    public var calendar: Calendar

    public init(
      features: WidgetFeatures, snapshot: WidgetSnapshot?, hasDrawing: Bool, calendar: Calendar
    ) {
      self.features = features
      self.snapshot = snapshot
      self.hasDrawing = hasDrawing
      self.calendar = calendar
    }
  }

  /// What a widget has to show at one moment.
  public enum Choice: Equatable, Sendable {
    case picture(PictureMode)
    case allOff
    /// Some are on, but none has anything to show yet.
    case nothingYet
  }

  /// The pictures that are on and have something to show at `now`, most pressing first.
  public static func available(_ inputs: Inputs, at now: Date) -> [PictureMode] {
    let snapshot = inputs.snapshot?.current(now: now, calendar: inputs.calendar)
    return PictureMode.allCases.filter { mode in
      guard inputs.features.isOn(mode.feature) else { return false }
      switch mode {
      case .partnerDrawing: return inputs.hasDrawing
      case .partnerWindow: return snapshot != nil
      case .streak: return (snapshot?.streak ?? 0) > 0
      case .daysTogether: return snapshot?.pairedSince != nil
      case .timeOfDay: return true
      case .nudge:
        guard let snapshot, snapshot.pairedSince != nil else { return false }
        let quiet = snapshot.daysSinceLastSent(now: now, calendar: inputs.calendar)
        return (quiet ?? nudgeAfterDays) >= nudgeAfterDays
      }
    }
  }

  /// The one picture at `now`. With rotation on, the pictures take turns by the clock, so every
  /// widget on the screen agrees; with it off, the most pressing one stays.
  public static func choice(_ inputs: Inputs, at now: Date) -> Choice {
    let modes = available(inputs, at: now)
    if modes.isEmpty {
      let anyOn = PictureMode.allCases.contains { inputs.features.isOn($0.feature) }
      return anyOn ? .nothingYet : .allOff
    }
    guard inputs.features.isOn(.rotatePictures), modes.count > 1 else {
      return .picture(modes[0])
    }
    let turn = Int((now.timeIntervalSinceReferenceDate / slot).rounded(.down))
    return .picture(modes[((turn % modes.count) + modes.count) % modes.count])
  }

  /// The moments the choice may change within the horizon, starting now.
  public static func dates(_ inputs: Inputs, from now: Date) -> [Date] {
    let end = now.addingTimeInterval(horizon)
    let step: TimeInterval = inputs.features.isOn(.rotatePictures) ? slot : 60 * 60
    var dates = [now]
    var next = (now.timeIntervalSinceReferenceDate / step).rounded(.down) * step + step
    while Date(timeIntervalSinceReferenceDate: next) < end {
      dates.append(Date(timeIntervalSinceReferenceDate: next))
      next += step
    }
    return dates
  }
}
