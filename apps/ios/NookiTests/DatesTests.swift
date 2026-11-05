import Foundation
import Testing
@testable import Billet

@Suite struct DatesTests {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)

    private func store() -> (UsStore, WalletStore, [String]) {
        let walletPath = scratchFile("wallet.json"), usPath = scratchFile("us.json")
        let wallet = WalletStore(file: walletPath)
        return (UsStore(wallet: wallet, file: usPath), wallet, [walletPath, usPath])
    }

    private func plan(_ ideaID: Int, at date: Date) -> PlannedDate {
        PlannedDate(ideaID: ideaID, date: date, organizer: "L")
    }

    @Test func aMatchNeedsBothPartnersToLoveTheIdea() {
        let (us, wallet, paths) = store()
        defer { paths.forEach(removeScratch) }
        let coins = wallet.wallet.coins

        us.swipe(1, liked: true, by: "L")
        #expect(!us.isMatch(1))
        #expect(us.matches.isEmpty)

        us.swipe(1, liked: true, by: "M")
        #expect(us.isMatch(1))
        #expect(us.matches.map(\.id) == [1])
        #expect(wallet.wallet.coins == coins + 10)
    }

    @Test func onePassMeansNoMatch() {
        let (us, _, paths) = store()
        defer { paths.forEach(removeScratch) }

        us.swipe(2, liked: true, by: "L")
        us.swipe(2, liked: false, by: "M")
        #expect(!us.isMatch(2))
        #expect(us.matches.isEmpty)
    }

    @Test func aPlannedMatchLeavesToPlan() {
        let (us, _, paths) = store()
        defer { paths.forEach(removeScratch) }
        us.swipe(3, liked: true, by: "L")
        us.swipe(3, liked: true, by: "M")

        us.upsertPlan(plan(3, at: now))
        #expect(us.matches.isEmpty)
        #expect(us.comingUp.map(\.ideaID) == [3])
    }

    @Test func eachPartnerKeepsTheirOwnDeck() {
        let (us, _, paths) = store()
        defer { paths.forEach(removeScratch) }
        let first = us.deck(for: "L", filter: DateFilter()).first!.id

        us.swipe(first, liked: true, by: "L")
        #expect(!us.deck(for: "L", filter: DateFilter()).contains { $0.id == first })
        #expect(us.deck(for: "M", filter: DateFilter()).first?.id == first)
    }

    @Test func doneDatesMoveOutOfComingUpWithTheirPhoto() {
        let (us, wallet, paths) = store()
        defer { paths.forEach(removeScratch) }
        let later = plan(4, at: now.addingTimeInterval(86_400))
        let past = plan(5, at: now.addingTimeInterval(-86_400))
        us.upsertPlan(later)
        us.upsertPlan(past)
        #expect(us.comingUp.map(\.id) == [past.id, later.id])

        let coins = wallet.wallet.coins
        let photo = UUID()
        us.rate(past.id, hearts: 3, momentID: photo)
        us.rate(past.id, hearts: 2)
        #expect(us.comingUp.map(\.id) == [later.id])
        #expect(us.done.map(\.id) == [past.id])
        #expect(us.done.first?.rating == 2)
        #expect(us.done.first?.momentID == photo)
        // Rating again changes the hearts but pays once.
        #expect(wallet.wallet.coins == coins + 30)
    }

    @Test func remindersSkipLeadsAlreadyPast() {
        let inTwoDays = now.addingTimeInterval(2 * 86_400)
        #expect(DateReminders.fireDates(for: inTwoDays, now: now).map(\.1)
            == [inTwoDays.addingTimeInterval(-86_400), inTwoDays.addingTimeInterval(-3_600)])

        let tonight = now.addingTimeInterval(5 * 3_600)
        #expect(DateReminders.fireDates(for: tonight, now: now).map(\.0) == [.hour])

        let soon = now.addingTimeInterval(30 * 60)
        #expect(DateReminders.fireDates(for: soon, now: now).isEmpty)
    }

    @Test func plansSavedBeforeRemindersStillLoad() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","ideaID":7,"date":0,"place":"","#
            + #""organizer":"L","surprise":false,"hint":""}"#
        let decoded = try JSONDecoder().decode(PlannedDate.self, from: Data(old.utf8))
        #expect(decoded.remind == nil)
        #expect(decoded.momentID == nil)
    }
}
