import Foundation

/// One experiment the owner can switch on or off in Settings. The raw value is the key it is
/// stored under, beside the widget features.
///
/// An experiment that cannot get in the way of drawing, sending and reading notes starts on. The
/// ones that stand in for the partner, or change what the cat does, start off. What the cat does
/// is not an experiment: its needs, its brain and its moments are always on.
public enum LabExperiment: String, CaseIterable, Codable, Sendable, FeatureFlag {
  case fakePartner
  case drawnReplay
  case todaysWord
  case sundayPost
  case sealedNote
  case wallpaperShortcut
  case porchLight
  case lampColours
  case lightsOut
  case nextVisit
  case onThisDay
  case wrappedDelivery
  case advent
  case bedsideHouse
  case shelfBoard
  case notesDesk
  case lifeBubble
  case lifeRings
  case lifeChips
  case lifeDebug
  case brainDebug

  public enum Group: CaseIterable, Sendable {
    case demo
    case cat
    case notes
    case home
    case firstLaunch

    public var title: String {
      switch self {
      case .demo: "Try it alone"
      case .cat: "The cat"
      case .notes: "Notes"
      case .home: "The house"
      case .firstLaunch: "First launch"
      }
    }
  }

  public var group: Group {
    switch self {
    case .fakePartner: .demo
    case .drawnReplay: .notes
    case .todaysWord: .notes
    case .sundayPost: .notes
    case .sealedNote: .notes
    case .wallpaperShortcut: .notes
    case .porchLight: .cat
    case .lampColours: .home
    case .lightsOut: .home
    case .nextVisit: .home
    case .onThisDay: .notes
    case .wrappedDelivery: .cat
    case .advent: .notes
    case .bedsideHouse: .home
    case .shelfBoard: .notes
    case .notesDesk: .notes
    case .lifeBubble: .cat
    case .lifeRings: .cat
    case .lifeChips: .cat
    case .lifeDebug: .cat
    case .brainDebug: .cat
    }
  }

  public var title: String {
    switch self {
    case .fakePartner: "Fake partner"
    case .drawnReplay: "Watch it being drawn"
    case .todaysWord: "Today's word"
    case .sundayPost: "Sunday post"
    case .sealedNote: "Sealed note"
    case .wallpaperShortcut: "Wallpaper shortcut"
    case .porchLight: "Porch light"
    case .lampColours: "Lamp colours"
    case .lightsOut: "Lights out"
    case .nextVisit: "Next visit"
    case .onThisDay: "On this day"
    case .wrappedDelivery: "Wrapped delivery"
    case .advent: "Our advent"
    case .bedsideHouse: "Bedside house"
    case .shelfBoard: "Shelf board"
    case .notesDesk: "Notes desk"
    case .lifeBubble: "Thought bubble"
    case .lifeRings: "Need rings"
    case .lifeChips: "Need words"
    case .lifeDebug: "Life debug"
    case .brainDebug: "Brain debug"
    }
  }

  public var detail: String {
    switch self {
    case .lifeBubble:
      "A small thought bubble floats over the cat when one need is low: a fish, a ball, a heart or a z. Tap it to answer."
    case .lifeRings:
      "A long press on the cat pulls up its portrait in four soft rings, one per need, with no numbers."
    case .lifeChips:
      "Four small words under the room, Full, Rested, Loved and Playful, glow when the need is met and fade when it is not."
    case .lifeDebug:
      "A small card on Home with the cat's four needs and mood, a faster clock and a button for each event. What it adds stays on this phone."
    case .brainDebug:
      "A card on Home shows what the brain is doing and why: its state, the five best scores, the last ten moves, its traits and favourite spot, and a faster clock."
    case .notesDesk:
      "Notes becomes a desk under a board: tap the paper to draw, tap a pinned note to open it. The list is one tap away. Off, Notes is the list."
    case .shelfBoard:
      "A warm wall of shelves, reached from Notes: every note you have sent each other, the newest large and forward, and numbered places for the next days of the streak."
    case .fakePartner:
      "A scripted partner on this phone sends notes, treats and hearts. Nothing is sent to anyone."
    case .bedsideHouse:
      "A small widget for StandBy: the sleeping cat and the latest note on a dark ground. Add it from the widget gallery. Only an iPhone on a stand can show it."
    case .advent:
      "Twenty-four small doors. Draw behind some for your partner; the ones they filled open from their day in December. Before then the doors can be filled but not opened. The fake partner fills doors 3, 9, 15 and 21."
    case .wrappedDelivery:
      "Give a piece or a treat from the closet. It lands wrapped on the partner's doormat, they unwrap it, and the cat is already in the box. No money: an item only moves between closets. The fake partner has its own closet and sends a gift now and then."
    case .onThisDay:
      "The cat digs out a note from this day a year ago, or a month ago. It needs history: the fake partner starts with one note of each."
    case .nextVisit:
      "Set the day you next meet. Home counts down, and a small suitcase by the door fills up as it nears. The day is kept on this phone."
    case .lightsOut:
      "Say goodnight and your lamp goes out. When both are out the cat curls up and the house goes dark. The fake partner puts its lamp out eight seconds after you."
    case .lampColours:
      "Choose a lamp colour for how today feels. Your partner's window shows theirs. No labels. The fake partner changes its colour now and then."
    case .porchLight:
      "Going away? Leave the porch light on for up to three nights and the streak waits for you. Free, always."
    case .wallpaperShortcut:
      "A Shortcuts action returns your partner's latest note on the night sky, sized for the Lock Screen. A received note also offers Make a wallpaper to save its picture."
    case .sealedNote:
      "Seal a note until tomorrow morning: the cat sits on it, with a countdown, and it goes when the time comes. With the fake partner, one of its notes arrives sealed for 90 seconds."
    case .sundayPost:
      "On Sundays the cat brings one page of the week's notes, from the notes on this phone, to save or share. Other days Home offers a peek at the week so far."
    case .todaysWord:
      "One small thing to draw each day, like lunch or your walk home. Both phones show the same word, with nothing sent between them."
    case .drawnReplay:
      "Open a note and the ink appears stroke by stroke, in the order it was drawn. The pace is made up, since notes carry no timestamps."
    }
  }

  /// Whether it adds a card to the Labs sheet on Home.
  public var hasHomeCard: Bool {
    switch self {
    case .fakePartner: false
    case .drawnReplay: false
    case .todaysWord: true
    case .sundayPost: true
    case .sealedNote: true
    case .wallpaperShortcut: false
    case .porchLight: true
    case .lampColours: true
    case .lightsOut: true
    case .nextVisit: true
    case .onThisDay: true
    case .wrappedDelivery: true
    case .advent: true
    case .bedsideHouse: false
    case .shelfBoard: false
    case .notesDesk: false
    case .lifeBubble: false
    case .lifeRings: false
    case .lifeChips: false
    case .lifeDebug: false
    case .brainDebug: false
    }
  }

  public var defaultOn: Bool {
    switch self {
    case .fakePartner: false
    case .drawnReplay: true
    case .todaysWord: true
    case .sundayPost: true
    case .sealedNote: true
    case .wallpaperShortcut: true
    case .porchLight: true
    case .lampColours: true
    case .lightsOut: true
    case .nextVisit: true
    case .onThisDay: true
    case .wrappedDelivery: true
    case .advent: true
    case .bedsideHouse: true
    case .shelfBoard: true
    case .notesDesk: true
    case .lifeBubble: false
    case .lifeRings: false
    case .lifeChips: false
    case .lifeDebug: false
    case .brainDebug: false
    }
  }
}
