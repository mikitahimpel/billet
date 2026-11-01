import Foundation

/// One switchable widget or Lock Screen behaviour. The raw value is the key it is stored under.
public enum WidgetFeature: String, CaseIterable, Codable, Sendable {
  case partnerDrawing
  case catMood
  case streak
  case timeOfDay
  case partnerWindow
  case daysTogether
  case nudge
  case rotatePictures

  public enum Group: CaseIterable, Sendable {
    case pictures

    public var title: String {
      switch self {
      case .pictures: "Pictures"
      }
    }
  }

  public var group: Group {
    switch self {
    case .partnerDrawing, .catMood, .streak, .timeOfDay, .partnerWindow, .daysTogether, .nudge,
      .rotatePictures:
      .pictures
    }
  }

  public var title: String {
    switch self {
    case .partnerDrawing: "Partner's last drawing"
    case .catMood: "Cat mood"
    case .streak: "Streak"
    case .timeOfDay: "Time of day"
    case .partnerWindow: "Partner's window"
    case .daysTogether: "Days together"
    case .nudge: "A nudge"
    case .rotatePictures: "Rotate pictures"
    }
  }

  public var detail: String {
    switch self {
    case .partnerDrawing: "The newest note, drawn on the widget."
    case .catMood: "How the cat feels right now."
    case .streak: "Days in a row you both gave a treat."
    case .timeOfDay: "The little house under today's sky."
    case .partnerWindow: "The window glows while your partner is in billet."
    case .daysTogether: "How long you have been paired."
    case .nudge: "Asks for a drawing when it has been a while."
    case .rotatePictures: "Take turns through the pictures that are on."
    }
  }

  /// Whether the feature is on until the owner turns it off.
  public var defaultOn: Bool { true }
}
