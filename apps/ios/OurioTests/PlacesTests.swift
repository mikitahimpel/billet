import Foundation
import MomentsInterface
import OurioShared
import Persistence
import Testing
import UIKit
import UsInterface
import Wire
@testable import Billet

@Suite struct PlacesTests {
    private let path = "Tests/\(UUID().uuidString)-us.json"

    private func cleanUp() {
        SharedFile.flush()
        try? FileManager.default.removeItem(at: SharedFile.url(path))
    }

    private func travel(_ us: UsStore) -> UsList {
        us.addList(kind: .travel, title: "Places to go", icon: ListKind.travel.icon)
    }

    @Test func everyCountryHasANameAFlagAndAShapeOnTheMap() {
        #expect(Country.codes.count == 195)
        let english = Locale(identifier: "en")
        let map = WorldMap.bundled
        for code in Country.codes {
            #expect(Country.name(code, locale: english) != code, "\(code) has no name")
            #expect(UIImage(named: "flag-\(code.lowercased())") != nil, "\(code) has no flag")
            #expect(map.shapes[code]?.isEmpty == false, "\(code) is not on the map")
        }
    }

    @Test func theFlagEmojiIsTheTwoRegionalLetters() {
        #expect(Country.emoji("JP") == "🇯🇵")
        #expect(Country.emoji("pt") == "🇵🇹")
    }

    @Test func searchFindsACountryInThePhonesLanguageAndInEnglish() {
        let russian = Locale(identifier: "ru")
        #expect(Country.search("япо", locale: russian).first == "JP")
        #expect(Country.search("Jap", locale: russian).first == "JP")
        #expect(Country.search("ita", locale: Locale(identifier: "en")).first == "IT")
        #expect(Country.search("korea", locale: Locale(identifier: "en")).contains("KR"))
        #expect(Country.search(" ", locale: russian).isEmpty)
    }

    @Test func theCountIgnoresDuplicatesPlacesAndWhatIsStillToGo() throws {
        defer { cleanUp() }
        let us = UsStore(file: path, onEarn: { _ in })
        let list = travel(us)
        us.addItem("Japan", to: list.id, author: "L", details: ListItemDetails(country: "JP"))
        us.addItem("Japan", to: list.id, author: "M", details: ListItemDetails(country: "JP"))
        us.addItem("Kyoto", to: list.id, author: "M", details: ListItemDetails(country: "JP", place: true))
        us.addItem("Lisbon", to: list.id, author: "L", details: ListItemDetails(country: "PT", place: true))
        us.addItem("Iceland", to: list.id, author: "L", details: ListItemDetails(country: "IS"))
        for item in try #require(us.list(list.id)).items where item.text != "Iceland" {
            us.setItem(item.id, in: list.id, done: true)
        }

        let been = try #require(us.list(list.id))
        #expect(been.beenCountries == ["JP"])
        #expect(been.wantedCountries == ["IS"])
        #expect(been.travelSummary.been == 1)
        #expect(been.travelSummary.percent == 1)
    }

    @Test func aPlaceBringsItsCountryAndACountryGoesInOnce() throws {
        defer { cleanUp() }
        let us = UsStore(file: path, onEarn: { _ in })
        let list = travel(us)
        us.addTravel(country: "JP", place: "Kyoto", to: list.id, author: "L")
        us.addTravel(country: "JP", place: "Osaka", to: list.id, author: "M")
        us.addTravel(country: "JP", to: list.id, author: "M")

        let items = try #require(us.list(list.id)).items
        #expect(items.filter(\.isCountry).count == 1)
        #expect(Set(items.filter(\.place).map(\.text)) == ["Kyoto", "Osaka"])

        let rows = PlaceRow.rows(of: try #require(us.list(list.id)))
        #expect(rows.want.count == 1)
        #expect(rows.want.first?.places.map(\.text) == ["Kyoto", "Osaka"])
    }

    @Test func markingBeenKeepsTheMonthAndPhotosForTheRoom() throws {
        defer { cleanUp() }
        let us = UsStore(file: path, onEarn: { _ in })
        let list = travel(us)
        us.addTravel(country: "IS", to: list.id, author: "L")
        let item = try #require(us.list(list.id)?.items.first)
        let photo = UUID()

        us.markBeen(item.id, in: list.id, month: TravelMonth(year: 2026, month: 10), moments: [photo], by: "M")

        let been = try #require(us.list(list.id)?.items.first)
        #expect(been.done != nil)
        #expect(been.doneBy == "M")
        #expect(been.visitedIn == "2026-10")
        #expect(been.moments == [photo])
        #expect(been.details.moments == [photo.uuidString])
        #expect(us.list(list.id)?.beenCountries == ["IS"])
    }

    @Test func aMonthReadsBackAndRefusesNonsense() {
        #expect(TravelMonth("2026-10") == TravelMonth(year: 2026, month: 10))
        #expect(TravelMonth(year: 2026, month: 3).text == "2026-03")
        #expect(TravelMonth("2026-13") == nil)
        #expect(TravelMonth("October") == nil)
    }

    @Test func aPlaceRoundTripsTheWire() throws {
        var item = Billet.ListItem(text: "Kyoto", author: "L")
        item.details = ListItemDetails(country: "JP", place: true, visitedIn: "2025-04",
                                       moments: ["00000000-0000-4000-8000-0000000000D1"])
        #expect(item.place)
        #expect(item.moments == [UUID(uuidString: "00000000-0000-4000-8000-0000000000D1")])
        let decoded = try JSONDecoder().decode(Billet.ListItem.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
    }
}
