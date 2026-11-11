import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import Testing
import Transport
import UsInterface
import Wire
@testable import Billet

private let arrival = ItemMedia(kind: .movie, tmdb: 329_865, year: 2016)
private let severance = ItemMedia(kind: .tv, tmdb: 95_396)
private let pastLives = ItemMedia(kind: .movie, tmdb: 666_277)

private func watchList() -> UsList {
    var watched = ListItem(text: "Severance", author: "A", media: severance, wants: ["A"])
    watched.done = .now
    return UsList(kind: .watch, title: "To watch", icon: ListKind.watch.icon, items: [
        ListItem(text: "Arrival", author: "A", media: arrival, wants: ["A", "L"]),
        ListItem(text: "Taco night film", author: "L"),
        watched,
    ])
}

/// The pair's room as the model sees it: a ♥ from both is a match, answered to the second swipe.
private nonisolated final class FakePickRoom: @unchecked Sendable {
    var swipes: [PickSwipe] = []
    var partnerWants: Set<String> = []
    var offline = false
    /// The next swipe is stored but its answer is lost, as when the connection drops on the way back.
    var losesNextAnswer = false
    var matches: [PickMatch] = []

    var sync: PickTonightSync {
        PickTonightSync(
            fetch: { () throws(TransportError) in
                if self.offline { throw .network("offline") }
                return PickTonightResponse(swipes: self.swipes, partnerPicked: self.partnerWants.count)
            },
            swipe: { request throws(TransportError) in
                if self.offline { throw .network("offline") }
                self.swipes.append(PickSwipe(title: request.title, choice: request.choice, at: 1))
                let key = PickTonightModel.key(request.title)
                let repeated = self.swipes.dropLast().contains { PickTonightModel.key($0.title) == key }
                let match = request.choice == .want && self.partnerWants.contains(key) && !repeated
                    ? PickMatch(title: request.title, name: request.name, at: 2) : nil
                if let match { self.matches.append(match) }
                if self.losesNextAnswer {
                    self.losesNextAnswer = false
                    throw .network("lost")
                }
                return PickTonightResponse(swipes: self.swipes, partnerPicked: self.partnerWants.count,
                                           matches: self.matches, match: match)
            })
    }
}

private func titles(_ suggested: [TitleSummary]) -> TitleSource {
    TitleSource(
        search: { _ throws(TransportError) in [] },
        details: { _, _ throws(TransportError) in throw .api(.notFound) },
        recommendations: { _ throws(TransportError) in suggested })
}

struct PickTonightTests {
    @Test func dealsTheListStillToWatchThenSuggestionsNotOnIt() {
        let list = watchList()
        let suggested = [
            TitleSummary(kind: .movie, tmdb: pastLives.tmdb, title: "Past Lives"),
            TitleSummary(kind: .movie, tmdb: arrival.tmdb, title: "Arrival"),
            TitleSummary(kind: .tv, tmdb: severance.tmdb, title: "Severance"),
        ]
        let deck = PickTonightModel.deck(list, swiped: [], suggestions: suggested)
        #expect(deck.map(\.name) == ["Arrival", "Taco night film", "Past Lives"])
        #expect(deck.map { $0.itemID != nil } == [true, true, false])

        let swiped = PickTonightModel.deck(list, swiped: [deck[0].id, "movie:\(pastLives.tmdb)"], suggestions: suggested)
        #expect(swiped.map(\.name) == ["Taco night film"])
    }

    @Test func suggestsFromWhatBothWantFirst() {
        var list = watchList()
        list.items.insert(ListItem(text: "Past Lives", author: "L", media: pastLives, wants: ["L"]), at: 0)
        let seeds = PickTonightModel.seeds(list, partners: ["A", "L"])
        #expect(seeds.map(\.tmdb) == [arrival.tmdb, pastLives.tmdb, severance.tmdb])
    }

    @Test func keysAListItemTheSameWhateverTheCaseOfItsID() {
        let id = UUID()
        #expect(PickTonightModel.key(.item(IdempotencyKey(id.uuidString.lowercased())))
            == PickTonightModel.key(.item(UsStore.key(id))))
    }

    @Test func showsAMatchOnceWhetherTheSwipeOrTheSocketBringsItFirst() async {
        let room = FakePickRoom()
        let list = watchList()
        let arrivalItem = list.items[0]
        room.partnerWants = [PickTonightModel.key(.item(UsStore.key(arrivalItem.id)))]
        let model = PickTonightModel(sync: room.sync, titles: titles([]))
        await model.load(list, partners: ["A", "L"])
        #expect(model.partnerPicked == 1)
        #expect(model.deck.count == 2)

        let card = model.deck[0]
        model.take(card)
        let match = await model.send(card, .want)
        #expect(match?.name == "Arrival")
        #expect(model.match == match)
        #expect(!model.matchByPartner)
        #expect(model.deck.map(\.name) == ["Taco night film"])

        model.dismissMatch()
        #expect(model.received(match!) == nil)
        #expect(model.match == nil)

        let theirs = PickMatch(title: .title(kind: .movie, tmdb: pastLives.tmdb), name: "Past Lives", at: 3)
        #expect(model.received(theirs) == theirs)
        #expect(model.matchByPartner)
    }

    @Test func keepsTheDeckButSendsNothingOffline() async {
        let room = FakePickRoom()
        room.offline = true
        let model = PickTonightModel(sync: room.sync, titles: titles([TitleSummary(kind: .movie, tmdb: 1, title: "X")]))
        await model.load(watchList(), partners: ["A", "L"])
        #expect(model.offline)
        #expect(model.deck.map(\.name) == ["Arrival", "Taco night film"])
        let card = model.deck[0]
        model.take(card)
        #expect(await model.send(card, .want) == nil)
        #expect(room.swipes.isEmpty)
    }

    @Test func putsAnUnsentSwipeBackAndFindsItsMatchOnTheRetry() async {
        let room = FakePickRoom()
        let list = watchList()
        room.partnerWants = [PickTonightModel.key(.item(UsStore.key(list.items[0].id)))]
        let model = PickTonightModel(sync: room.sync, titles: titles([]))
        await model.load(list, partners: ["A", "L"])

        let card = model.deck[0]
        model.take(card)
        room.losesNextAnswer = true
        #expect(await model.send(card, .want) == nil)
        #expect(model.unsent)
        #expect(model.deck.first == card)
        #expect(model.match == nil)

        model.take(card)
        #expect(!model.unsent)
        let match = await model.send(card, .want)
        #expect(match?.name == "Arrival")
        #expect(model.match == match)
    }

    @Test func cutsALongNameToWhatTheRoomTakesWithoutSplittingACharacter() {
        #expect(PickTonightModel.wireName("Arrival") == "Arrival")
        let long = String(repeating: "a", count: 299) + "👩‍👩‍👧"
        #expect(PickTonightModel.wireName(long) == String(repeating: "a", count: 299))
        #expect(PickTonightModel.wireName(String(repeating: "b", count: 400)).utf16.count == 300)
    }

    @Test func plansTonightAtEightOrTheNextHalfHour() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let day = { (hour: Int, minute: Int) in
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: hour, minute: minute))!
        }
        #expect(PickTonightScreen.tonight(now: day(17, 10), calendar: calendar) == day(20, 0))
        #expect(PickTonightScreen.tonight(now: day(19, 45), calendar: calendar) == day(20, 0))
        #expect(PickTonightScreen.tonight(now: day(21, 10), calendar: calendar) == day(21, 30))
        #expect(PickTonightScreen.tonight(now: day(21, 40), calendar: calendar) == day(22, 0))
    }
}
