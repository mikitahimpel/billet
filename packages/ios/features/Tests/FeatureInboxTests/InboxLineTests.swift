import Testing
import Wire

@testable import FeatureInbox

private let titles = ["lamp": "Mushroom Lamp", "rug": "Round Rug", "monstera": "Monstera"]
private var names: InboxLine.Names {
  InboxLine.Names(
    partner: "Anya", cat: "Mochi", title: { titles[$0] },
    mood: { $0 == .missing ? "missing you" : $0.rawValue },
    list: { $0 == .groceries ? "basket.fill" : "list.bullet" },
    reaction: { $0 == .heart ? "❤️" : "?" })
}

private func item(_ event: ActivityEvent, _ actor: ActivityActor = .partner) -> ActivityItem {
  ActivityItem(id: "x", at: 0, actor: actor, event: event, target: nil, cursor: "0~x")
}

@Suite struct InboxLineTests {
  @Test func linesNameWhoDidIt() {
    #expect(InboxLine(item(.catFed(grams: 40)), names: names).text == "Anya fed Mochi 40 g")
    #expect(InboxLine(item(.catFed(grams: 40), .me), names: names).text == "You fed Mochi 40 g")
    #expect(InboxLine(item(.catSlept, .cat), names: names).text == "Mochi had a nap")
    #expect(
      InboxLine(item(.streakReached(days: 12)), names: names).text == "Your streak is 12 days")
  }

  @Test func notesSayWhatWasSentAndToWhom() {
    let drawing = ActivityEvent.noteSent(note: NoteId("n"), kind: "Drawing")
    #expect(InboxLine(item(drawing), names: names).text == "Anya sent you a drawing")
    #expect(InboxLine(item(drawing, .me), names: names).text == "You sent a drawing")
    #expect(
      InboxLine(item(.noteSent(note: NoteId("n"), kind: "Text")), names: names).text
        == "Anya sent you a note")
  }

  @Test func shopLinesUseTheCatalogueTitles() {
    let one = ActivityEvent.purchased(offer: nil, items: ["lamp"], coins: 140)
    #expect(
      InboxLine(item(one, .me), names: names).text == "You bought the Mushroom Lamp for 140 coins")
    let many = ActivityEvent.purchased(offer: nil, items: ["lamp", "rug"], coins: 300)
    #expect(InboxLine(item(many), names: names).text == "Anya bought 2 things for 300 coins")
    #expect(
      InboxLine(item(.plantWatered(plant: "monstera")), names: names).text
        == "Anya watered the monstera")
    #expect(
      InboxLine(item(.plantWatered(plant: nil)), names: names).text == "Anya watered the plant")
  }

  @Test func aSharedMoodShowsItsFace() {
    let line = InboxLine(item(.moodShared(mood: .missing)), names: names)
    #expect(line.text == "Anya feels missing you")
    #expect(line.mood == .missing)
    #expect(InboxLine(item(.moodShared(mood: .happy), .me), names: names).text == "You feel happy")
  }

  @Test func reactionsAndListsUseTheAppsSymbols() {
    let reacted = ActivityEvent.reacted(note: NoteId("n"), reaction: .heart)
    #expect(InboxLine(item(reacted), names: names).text == "Anya reacted ❤️ to your photo")
    let added = ActivityEvent.listItemAdded(
      list: IdempotencyKey("l"), kind: .groceries, title: "Groceries", count: 1, text: "milk")
    let line = InboxLine(item(added), names: names)
    #expect(line.symbol == "basket.fill")
    #expect(line.text == "Anya added “milk” to Groceries")
  }

  @Test func unknownIdsReadAsWords() {
    #expect(InboxLine.readable("rainy-evening") == "Rainy evening")
  }
}

@Suite struct InboxLayoutTests {
  private static let page = InboxMachine.Page(items: [
    ActivityItem(id: "x", at: 0, actor: .partner, event: .catPetted, target: nil, cursor: "0~x")
  ])

  @Test func shortStatesFitTheirContent() {
    let empty = InboxMachine.Page(items: [])
    let short: [InboxMachine.Sheet] = [
      .idle, .loading, .unpaired, .failed, .loaded(empty), .stale(empty),
    ]
    for sheet in short {
      let layout = InboxLayout(sheet)
      #expect(layout == .short)
      #expect(layout.size == .fit)
      #expect(layout.scrolls, "a fitted sheet measures its content through its own scroll view")
    }
  }

  @Test func itemsTakeTheWholeSheet() {
    for sheet: InboxMachine.Sheet in [
      .loaded(Self.page), .refreshing(Self.page), .stale(Self.page),
    ] {
      let layout = InboxLayout(sheet)
      #expect(layout == .list)
      #expect(layout.size == .large)
      #expect(!layout.scrolls)
    }
  }
}
