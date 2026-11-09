import Design
import FeatureInbox
import Foundation
import Testing
import Wire
@testable import Billet

private let names = InboxLine.Names(partner: "Anya", cat: "Mochi", title: { Catalog.item($0)?.name })

private nonisolated func item(_ event: ActivityEvent, _ actor: ActivityActor = .partner, id: String = "x", at: Int = 0)
    -> ActivityItem
{
    ActivityItem(id: id, at: at, actor: actor, event: event)
}

@Suite struct InboxLineTests {
    @Test func linesNameWhoDidIt() {
        #expect(InboxLine(item(.catFed(grams: 40)), names: names).text == "Anya fed Mochi 40 g")
        #expect(InboxLine(item(.catFed(grams: 40), .me), names: names).text == "You fed Mochi 40 g")
        #expect(InboxLine(item(.catSlept, .cat), names: names).text == "Mochi had a nap")
        #expect(InboxLine(item(.streakReached(days: 12)), names: names).text == "Your streak is 12 days")
    }

    @Test func notesSayWhatWasSentAndToWhom() {
        let drawing = ActivityEvent.noteSent(note: NoteId("n"), kind: "Drawing")
        #expect(InboxLine(item(drawing), names: names).text == "Anya sent you a drawing")
        #expect(InboxLine(item(drawing, .me), names: names).text == "You sent a drawing")
        #expect(InboxLine(item(.noteSent(note: NoteId("n"), kind: "Text")), names: names).text == "Anya sent you a note")
    }

    @Test func shopLinesUseTheCatalogueTitles() {
        let one = ActivityEvent.purchased(offer: nil, items: ["lamp"], coins: 140)
        #expect(InboxLine(item(one, .me), names: names).text == "You bought the Mushroom Lamp for 140 coins")
        let many = ActivityEvent.purchased(offer: nil, items: ["lamp", "rug"], coins: 300)
        #expect(InboxLine(item(many), names: names).text == "Anya bought 2 things for 300 coins")
        #expect(InboxLine(item(.plantWatered(plant: "monstera")), names: names).text == "Anya watered the monstera")
        #expect(InboxLine(item(.plantWatered(plant: nil)), names: names).text == "Anya watered the plant")
    }

    @Test func unknownIdsReadAsWords() {
        #expect(InboxLine.readable("rainy-evening") == "Rainy evening")
    }
}

@MainActor @Suite(.serialized) struct InboxTargetTests {
    @Test func aTextNoteWaitsToBeSentAndThenOpensFromItsRow() throws {
        let state = HomeState(stores: .live())
        let note = try #require(state.notes.add(text: "dinner at 8?", paper: .sky, author: state.viewer))
        defer { state.notes.delete(note) }
        #expect(state.notes.unsent.map(\.id) == [note.id])

        state.notes.setSent(note.id, noteID: "note-sent-1")
        #expect(state.notes.unsent.isEmpty)
        state.open(.note(NoteId("note-sent-1")))
        #expect(state.tab == .moments)
        #expect(state.openedPin?.id == note.id)
    }

    @Test func thePartnersNoteKeepsItsDateOrderAndComesOnce() throws {
        let state = HomeState(stores: .live())
        let date = Date(timeIntervalSince1970: 1_000)
        state.notes.addReceived(text: "hi", paper: .blush, ink: nil, author: state.otherPartner, date: date,
                                noteID: "note-in-1")
        state.notes.addReceived(text: "hi", paper: .blush, ink: nil, author: state.otherPartner, date: date,
                                noteID: "note-in-1")
        let received = try #require(state.notes.note(noteID: "note-in-1"))
        defer { state.notes.delete(received) }
        #expect(state.notes.notes.filter { $0.noteID == "note-in-1" }.count == 1)
        #expect(received.unsent == nil)
        #expect(state.notes.notes.last?.id == received.id || state.notes.notes.allSatisfy { $0.date >= date })
    }

    @Test func aRowForSomethingThisPhoneLacksOpensItsTab() {
        let state = HomeState(stores: .live())
        state.open(.moments(NoteId("not-on-this-phone")))
        #expect(state.tab == .moments)
        #expect(state.openedPin == nil)
    }
}

@Suite struct InboxLinkTests {
    @Test func theInboxHasADeepLink() {
        #expect(DeepLink(url: DeepLink.inbox.url) == .inbox)
    }
}

@Suite struct InboxLayoutTests {
    private static let page = InboxMachine.Page(items: [ActivityItem(id: "x", at: 0, actor: .partner, event: .catPetted)])

    @Test func shortStatesFitTheirContent() {
        let empty = InboxMachine.Page(items: [])
        let short: [InboxMachine.Sheet] = [.idle, .loading, .unpaired, .failed, .loaded(empty), .stale(empty)]
        for sheet in short {
            let layout = InboxLayout(sheet)
            #expect(layout == .short)
            #expect(layout.size == .fit)
            #expect(layout.scrolls, "a fitted sheet measures its content through its own scroll view")
        }
    }

    @Test func itemsTakeTheWholeSheet() {
        for sheet: InboxMachine.Sheet in [.loaded(Self.page), .refreshing(Self.page), .stale(Self.page)] {
            let layout = InboxLayout(sheet)
            #expect(layout == .list)
            #expect(layout.size == .large)
            #expect(!layout.scrolls)
        }
    }
}
