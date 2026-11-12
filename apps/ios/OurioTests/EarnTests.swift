import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import Persistence
import ProfileInterface
import Testing
import UIKit
import UsInterface
import Wire
@testable import Billet

@MainActor
@Suite(.serialized) struct EarnTests {
    @Test func whatStaysOnThisPhoneEarnsAndWhatGoesToThePartnerDoesNot() throws {
        var earned: [EarnEvent] = []
        let moments = MomentStore(), notes = NoteStore()
        let journal = Journal(
            moments: moments, notes: notes, streak: StreakStore(file: "Tests/\(UUID().uuidString)-streak.json"),
            couple: CoupleStore()) { earned.append($0) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }

        #expect(journal.addNote(text: "dinner at 8?", paper: .sky))
        #expect(journal.addMoment(image, caption: "shared", shares: true))
        #expect(earned.isEmpty)

        let notesBefore = Set(notes.notes.map(\.id)), momentsBefore = Set(moments.moments.map(\.id))
        #expect(journal.addNote(doodle: image, paper: .sky))
        #expect(journal.addMoment(image, caption: "keepsake"))
        let doodle = try #require(notes.notes.first { !notesBefore.contains($0.id) })
        let keepsake = try #require(moments.moments.first { !momentsBefore.contains($0.id) })
        #expect(earned == [.noteAdded(note: doodle.id.uuidString), .momentAdded(moment: keepsake.id.uuidString)])

        for note in notes.notes where note.text == "dinner at 8?" || note.id == doodle.id { notes.delete(note) }
        for moment in moments.moments where moment.caption == "shared" || moment.id == keepsake.id {
            moments.delete(moment)
        }
    }

    @Test func theUsTabAsksForItsEarnsOncePerThing() throws {
        let path = "Tests/\(UUID().uuidString)-us.json"
        defer {
            SharedFile.flush()
            try? FileManager.default.removeItem(at: SharedFile.url(path))
        }
        var earned: [EarnEvent] = []
        let us = UsStore(file: path) { earned.append($0) }

        let wish = WishItem(owner: "L", title: "Scarf")
        us.upsertWish(wish)
        us.markReceived(wish.id, by: "L")
        us.markReceived(wish.id, by: "L")

        let idea = try #require(DateIdea.all.first)
        us.swipe(idea.id, liked: true, by: "L")
        us.swipe(idea.id, liked: true, by: "M")
        us.swipe(idea.id, liked: true, by: "M")

        let plan = PlannedDate(ideaID: idea.id, date: .now, organizer: "L")
        us.upsertPlan(plan)
        us.rate(plan.id, hearts: 3)
        us.rate(plan.id, hearts: 2)

        #expect(earned == [
            .wishReceived(wish: wish.id.uuidString), .dateMatched(idea: String(idea.id)),
            .dateRated(plan: plan.id.uuidString),
        ])
    }
}
