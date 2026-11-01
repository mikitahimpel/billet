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
  case buttonTreat
  case buttonPet
  case buttonHeart
  case lockScreenButtons
  case controlPet
  case controlHeart
  case controlCanvas
  case liveActivity
  case canvasShortcut
  case questionCard
  case doodleCard

  public enum Group: CaseIterable, Sendable {
    case pictures
    case buttons
    case controls
    case liveActivity
    case canvas

    public var title: String {
      switch self {
      case .pictures: "Pictures"
      case .buttons: "Buttons"
      case .controls: "Controls"
      case .liveActivity: "Live Activity"
      case .canvas: "Canvas"
      }
    }
  }

  public var group: Group {
    switch self {
    case .partnerDrawing, .catMood, .streak, .timeOfDay, .partnerWindow, .daysTogether, .nudge,
      .rotatePictures:
      .pictures
    case .buttonTreat, .buttonPet, .buttonHeart, .lockScreenButtons:
      .buttons
    case .controlPet, .controlHeart, .controlCanvas:
      .controls
    case .liveActivity:
      .liveActivity
    case .canvasShortcut, .questionCard, .doodleCard:
      .canvas
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
    case .buttonTreat: "Give today's treat"
    case .buttonPet: "Pet the cat"
    case .buttonHeart: "Send a heart"
    case .lockScreenButtons: "Buttons on the Lock Screen"
    case .controlPet: "Control: pet the cat"
    case .controlHeart: "Control: send a heart"
    case .controlCanvas: "Control: draw a note"
    case .liveActivity: "The cat is on its way"
    case .canvasShortcut: "Draw from a shortcut"
    case .questionCard: "Today's question"
    case .doodleCard: "Doodle prompt"
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
    case .buttonTreat: "A button on the Home Screen widget."
    case .buttonPet: "A button on the Home Screen widget."
    case .buttonHeart: "Answers your partner's newest note."
    case .lockScreenButtons: "Let the buttons run from Lock Screen widgets too."
    case .controlPet: "For the Lock Screen and Control Center."
    case .controlHeart: "For the Lock Screen and Control Center."
    case .controlCanvas: "Opens billet straight on the canvas."
    case .liveActivity: "Shows the cat carrying a note on the Lock Screen, with a heart button."
    case .canvasShortcut: "A Shortcuts action that opens billet straight on the canvas."
    case .questionCard: "A question to answer with a drawing, on Home."
    case .doodleCard: "Something small to doodle, on Home."
    }
  }

  /// Whether the feature is on until the owner turns it off.
  public var defaultOn: Bool {
    switch self {
    case .doodleCard: false
    default: true
    }
  }
}
