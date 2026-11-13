import DrawInterface
import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import Testing
import UsInterface
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
}
