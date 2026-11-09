import Foundation
import OurioShared
import Testing
import Wire
@testable import Billet

struct SharedMomentsTests {
    @Test func pushesUnderThePartnersNameReadAfterIt() {
        let photo = PushPayload.alert(noteId: NoteId("n1"), author: UserId("anya"), compact: nil)
        let text = PushPayload.alert(noteId: NoteId("n2"), author: UserId("anya"), compact: nil,
                                     text: NoteText(validating: "hi"))
        let reaction = PushPayload.reaction(noteId: NoteId("n1"), by: UserId("anya"), reaction: .fire)
        #expect(photo.bodyAfterName == "Sent you a photo")
        #expect(text.bodyAfterName == nil)
        #expect(reaction.bodyAfterName == "Reacted 🔥 to your photo")
    }

    @MainActor
    @Test func aReceiveWhileOneRunsGoesOnceMoreInsteadOfAlongside() async {
        let gate = PhotoReceiving()
        var runs = 0
        var overlapping = false
        var running = false
        func body() async {
            overlapping = overlapping || running
            running = true
            runs += 1
            if runs == 1 {
                await gate.run(body)
                await gate.run(body)
            }
            running = false
        }
        await gate.run(body)
        #expect(runs == 2)
        #expect(!overlapping)
    }
}
