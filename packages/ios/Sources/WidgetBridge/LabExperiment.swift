import Foundation

/// One experiment the owner can switch on or off in Settings. The raw value is the key it is
/// stored under, beside the widget features.
///
/// An experiment that cannot get in the way of drawing, sending and reading notes starts on. The
/// ones that stand in for the partner, or change what the cat does, start off.
public enum LabExperiment: String, CaseIterable, Codable, Sendable, FeatureFlag {
  case fakePartner
  case overnightStay
  case drawnReplay
  case catCameBack
  case todaysWord
  case sundayPost
  case framedNotes

  public enum Group: CaseIterable, Sendable {
    case demo
    case cat
    case notes

    public var title: String {
      switch self {
      case .demo: "Try it alone"
      case .cat: "The cat"
      case .notes: "Notes"
      }
    }
  }

  public var group: Group {
    switch self {
    case .fakePartner: .demo
    case .overnightStay: .cat
    case .drawnReplay: .notes
    case .catCameBack: .cat
    case .todaysWord: .notes
    case .sundayPost: .notes
    case .framedNotes: .notes
    }
  }

  public var title: String {
    switch self {
    case .fakePartner: "Fake partner"
    case .overnightStay: "Overnight stay"
    case .drawnReplay: "Watch it being drawn"
    case .catCameBack: "The cat came back"
    case .todaysWord: "Today's word"
    case .sundayPost: "Sunday post"
    case .framedNotes: "Framed notes"
    }
  }

  public var detail: String {
    switch self {
    case .fakePartner:
      "A scripted partner on this phone sends notes, treats and hearts. Nothing is sent to anyone."
    case .framedNotes:
      "Hang a received note in a frame from its full-screen view. Up to three frames hang on the wall of the room. The choice stays on this phone."
    case .sundayPost:
      "On Sundays the cat brings one page of the week's notes, from the notes on this phone, to save or share. Other days Home offers a peek at the week so far."
    case .todaysWord:
      "One small thing to draw each day, like lunch or your walk home. Both phones show the same word, with nothing sent between them."
    case .catCameBack:
      "Once your partner has opened your note, Home shows the cat back with an empty satchel for twelve hours."
    case .drawnReplay:
      "Open a note and the ink appears stroke by stroke, in the order it was drawn. The pace is made up, since notes carry no timestamps."
    case .overnightStay:
      "The cat stays with whoever got the last note. After you send one, a warm dent and paw prints wait until your partner sends one back."
    }
  }

  public var defaultOn: Bool {
    switch self {
    case .fakePartner: false
    case .overnightStay: true
    case .drawnReplay: true
    case .catCameBack: true
    case .todaysWord: true
    case .sundayPost: true
    case .framedNotes: true
    }
  }
}
