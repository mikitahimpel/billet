import Foundation

/// One experiment the owner can switch on or off in Settings. The raw value is the key it is
/// stored under, beside the widget features.
///
/// An experiment that cannot get in the way of drawing, sending and reading notes starts on. The
/// ones that stand in for the partner, or change what the cat does, start off, except the cat's
/// needs, which the owner wants on, shown in the room.
public enum LabExperiment: String, CaseIterable, Codable, Sendable, FeatureFlag {
  case fakePartner
  case overnightStay
  case drawnReplay
  case catCameBack
  case todaysWord
  case sundayPost
  case framedNotes
  case sealedNote
  case twoWisps
  case wallpaperShortcut
  case porchLight
  case lampColours
  case lightsOut
  case theirSky
  case nextVisit
  case onThisDay
  case seasons
  case wrappedDelivery
  case advent
  case bedsideHouse
  case shelfBoard
  case catCarriesNote
  case catPurrs
  case catBats
  case catGreets
  case catChases
  case shopScene
  case notesDesk
  case cinematicOnboarding
  case catLife
  case lifeInRoom
  case lifeBubble
  case lifeRings
  case lifeChips
  case lifeDebug
  case catBrain

  public enum Group: CaseIterable, Sendable {
    case demo
    case cat
    case notes
    case home
    case catMoments
    case firstLaunch

    public var title: String {
      switch self {
      case .demo: "Try it alone"
      case .cat: "The cat"
      case .notes: "Notes"
      case .home: "The house"
      case .catMoments: "Cat moments"
      case .firstLaunch: "First launch"
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
    case .sealedNote: .notes
    case .twoWisps: .cat
    case .wallpaperShortcut: .notes
    case .porchLight: .cat
    case .lampColours: .home
    case .lightsOut: .home
    case .theirSky: .home
    case .nextVisit: .home
    case .onThisDay: .notes
    case .seasons: .home
    case .wrappedDelivery: .cat
    case .advent: .notes
    case .bedsideHouse: .home
    case .shelfBoard: .notes
    case .catCarriesNote: .catMoments
    case .catPurrs: .catMoments
    case .catBats: .catMoments
    case .catGreets: .catMoments
    case .catChases: .catMoments
    case .shopScene: .home
    case .notesDesk: .notes
    case .cinematicOnboarding: .firstLaunch
    case .catLife: .cat
    case .lifeInRoom: .cat
    case .lifeBubble: .cat
    case .lifeRings: .cat
    case .lifeChips: .cat
    case .lifeDebug: .cat
    case .catBrain: .cat
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
    case .sealedNote: "Sealed note"
    case .twoWisps: "Two wisps"
    case .wallpaperShortcut: "Wallpaper shortcut"
    case .porchLight: "Porch light"
    case .lampColours: "Lamp colours"
    case .lightsOut: "Lights out"
    case .theirSky: "Their sky"
    case .nextVisit: "Next visit"
    case .onThisDay: "On this day"
    case .seasons: "Seasons"
    case .wrappedDelivery: "Wrapped delivery"
    case .advent: "Our advent"
    case .bedsideHouse: "Bedside house"
    case .shelfBoard: "Shelf board"
    case .catCarriesNote: "Carries the note"
    case .catPurrs: "Purrs when petted"
    case .catBats: "Bats at your finger"
    case .catGreets: "Greets you"
    case .catChases: "Plays on its own"
    case .shopScene: "Shop tab"
    case .notesDesk: "Notes desk"
    case .cinematicOnboarding: "Cinematic onboarding"
    case .catLife: "The cat's needs"
    case .lifeInRoom: "Needs in the room"
    case .lifeBubble: "Thought bubble"
    case .lifeRings: "Need rings"
    case .lifeChips: "Need words"
    case .lifeDebug: "Life debug"
    case .catBrain: "Cat brain"
    }
  }

  public var detail: String {
    switch self {
    case .catLife:
      "The cat gets hungry, sleepy, playful and wants to be loved by you both, and lets it show. Treats feed it, petting and notes most of all make it feel loved, playing with it keeps it lively, and it sleeps at night. It never gets sick, and a few days away hurt little."
    case .lifeInRoom:
      "With the cat's needs on, the room shows them: the bowl empties, a ball of yarn comes out when it wants to play, and the lamp burns warmer the more loved it feels."
    case .lifeBubble:
      "With the cat's needs on, a small thought bubble floats over the cat when one need is low: a fish, a ball, a heart or a z. Tap it to answer."
    case .lifeRings:
      "With the cat's needs on, a long press on the cat pulls up its portrait in four soft rings, one per need, with no numbers."
    case .lifeChips:
      "With the cat's needs on, four small words under the room, Full, Rested, Loved and Playful, glow when the need is met and fade when it is not."
    case .lifeDebug:
      "A small card on Home with the cat's four needs and mood, a faster clock and a button for each event. What it adds stays on this phone."
    case .catBrain:
      "The cat in the styled rooms runs on its brain: it naps in the sun, watches the rain, grooms after a meal, nudges a mug and waits by the window when one of you is away. Both phones see the same cat."
    case .catCarriesNote:
      "When a note arrives, the cat carries it in its mouth to the wall or the glass and tapes it up."
    case .catPurrs:
      "Stroke the cat for a soft purr under your finger and small floating hearts. Keep going and it rolls onto its back."
    case .catBats:
      "Touch near the edge of the screen and the cat notices, then bats at your finger."
    case .catGreets:
      "Open billet after a few hours away and the cat runs up to the camera and headbutts it."
    case .catChases:
      "Now and then the cat chases the yarn, or a dot of light from the lamp, all by itself."
    case .shopScene:
      "A Shop tab: a little 3D shop with a keeper behind the counter. Tap anything on the shelves to see it and buy it. The keeper is chosen under Shopkeeper. Off, the shop stays a sheet on Home."
    case .cinematicOnboarding:
      "First launch flies into a windowsill of candles with a soft beating heart, and pairing happens in that scene. Off, it is the plain welcome and code screens. Replay it below without touching your pair."
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
    case .seasons:
      "The house changes with the year: an autumn branch losing its leaves, snow building on the sill, a blossom branch in spring, a low sun in summer. Nothing to do. Northern hemisphere months."
    case .onThisDay:
      "The cat digs out a note from this day a year ago, or a month ago. It needs history: the fake partner starts with one note of each."
    case .nextVisit:
      "Set the day you next meet. Home counts down, and a small suitcase by the door fills up as it nears. The day is kept on this phone."
    case .theirSky:
      "Shows dawn, daytime, dusk or night where your partner is, from their time zone alone. The fake partner lives in Tokyo."
    case .lightsOut:
      "Say goodnight and your lamp goes out. When both are out the cat curls up and the house goes dark. The fake partner puts its lamp out eight seconds after you."
    case .lampColours:
      "Choose a lamp colour for how today feels. Your partner's window shows theirs. No labels. The fake partner changes its colour now and then."
    case .porchLight:
      "Going away? Leave the porch light on for up to three nights and the streak waits for you. Free, always."
    case .wallpaperShortcut:
      "A Shortcuts action returns your partner's latest note on the night sky, sized for the Lock Screen. A received note also offers Make a wallpaper to save its picture."
    case .twoWisps:
      "Hold the cat at the same moment as your partner, and the two chimney wisps cross into a heart, with a soft buzz. The fake partner holds for ten seconds now and then."
    case .sealedNote:
      "Seal a note until tomorrow morning: the cat sits on it, with a countdown, and it goes when the time comes. With the fake partner, one of its notes arrives sealed for 90 seconds."
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

  /// Whether it adds a card to the Labs sheet on Home.
  public var hasHomeCard: Bool {
    switch self {
    case .fakePartner: false
    case .overnightStay: false
    case .drawnReplay: false
    case .catCameBack: false
    case .todaysWord: true
    case .sundayPost: true
    case .framedNotes: false
    case .sealedNote: true
    case .twoWisps: true
    case .wallpaperShortcut: false
    case .porchLight: true
    case .lampColours: true
    case .lightsOut: true
    case .theirSky: true
    case .nextVisit: true
    case .onThisDay: true
    case .seasons: false
    case .wrappedDelivery: true
    case .advent: true
    case .bedsideHouse: false
    case .shelfBoard: false
    case .catCarriesNote: false
    case .catPurrs: false
    case .catBats: false
    case .catGreets: false
    case .catChases: false
    case .shopScene: false
    case .notesDesk: false
    case .cinematicOnboarding: false
    case .catLife: false
    case .lifeInRoom: false
    case .lifeBubble: false
    case .lifeRings: false
    case .lifeChips: false
    case .lifeDebug: false
    case .catBrain: false
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
    case .sealedNote: true
    case .twoWisps: true
    case .wallpaperShortcut: true
    case .porchLight: true
    case .lampColours: true
    case .lightsOut: true
    case .theirSky: true
    case .nextVisit: true
    case .onThisDay: true
    case .seasons: true
    case .wrappedDelivery: true
    case .advent: true
    case .bedsideHouse: true
    case .shelfBoard: true
    case .catCarriesNote: false
    case .catPurrs: false
    case .catBats: false
    case .catGreets: false
    case .catChases: false
    case .shopScene: true
    case .notesDesk: true
    case .cinematicOnboarding: true
    case .catLife: true
    case .lifeInRoom: true
    case .lifeBubble: false
    case .lifeRings: false
    case .lifeChips: false
    case .lifeDebug: false
    case .catBrain: false
    }
  }
}
