import Foundation
import Testing
import Wire
@testable import Billet

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
