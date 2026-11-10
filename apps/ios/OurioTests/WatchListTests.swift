import Foundation
import OurioShared
import Persistence
import Testing
import Wire
@testable import Billet

@Suite struct WatchListTests {
    private let path = "Tests/\(UUID().uuidString)-us.json"

    private func cleanUp() {
        SharedFile.flush()
        try? FileManager.default.removeItem(at: SharedFile.url(path))
    }

    private let arrival = ItemMedia(kind: .movie, tmdb: 329865, year: 2016, posterPath: "/evHCf9GuBDc42KvW9DRhY7pKx11.jpg")

    @Test func aTitleFromSearchKeepsItsPosterAndStartsWithItsAuthorsWant() {
        defer { cleanUp() }
        let us = UsStore(file: path, onEarn: { _ in })
        let list = us.addList(kind: .watch, title: "To watch", icon: ListKind.watch.icon)
        us.addItem("Arrival", to: list.id, author: "L", media: arrival)

        let item = us.list(list.id)?.items.first
        #expect(item?.media == arrival)
        #expect(item?.wants == ["L"])
        #expect(item?.details.media == ListMedia(kind: .movie, tmdb: 329865, year: 2016,
                                                 posterPath: "/evHCf9GuBDc42KvW9DRhY7pKx11.jpg"))
    }

    @Test func wantTooMakesItBothAndSaysSoOnce() throws {
        defer { cleanUp() }
        let us = UsStore(file: path, onEarn: { _ in })
        let list = us.addList(kind: .watch, title: "To watch", icon: ListKind.watch.icon)
        us.addItem("Arrival", to: list.id, author: "L", media: arrival)
        let item = try #require(us.list(list.id)?.items.first)

        us.setWant(item.id, in: list.id, wants: true, by: "M")
        us.setWant(item.id, in: list.id, wants: true, by: "M")
        #expect(us.list(list.id)?.items.first?.wants == ["L", "M"])

        us.setWant(item.id, in: list.id, wants: false, by: "L")
        #expect(us.list(list.id)?.items.first?.wants == ["M"])
    }

    @Test func aTitleAddedAsTextHasNoMediaAndNoWant() {
        defer { cleanUp() }
        let us = UsStore(file: path, onEarn: { _ in })
        let list = us.addList(kind: .watch, title: "To watch", icon: ListKind.watch.icon)
        us.addItem("Grandma's tape", to: list.id, author: "L")

        #expect(us.list(list.id)?.items.first?.media == nil)
        #expect(us.list(list.id)?.items.first?.wants == [])
    }

    @Test func captionsSayWhatTMDBKnows() {
        // The rating is written the phone's way, 7.6 or 7,6.
        let rating = 7.6.formatted(.number.precision(.fractionLength(1)))
        #expect(TitleCaption.of(TitleSummary(kind: .movie, tmdb: 1, title: "Arrival", year: 2016, rating: 7.6,
                                             runtime: 116)) == "2016 · Movie · 1 h 56 min · ★ \(rating)")
        #expect(TitleCaption.of(TitleSummary(kind: .tv, tmdb: 2, title: "Arrival", year: 2024, seasons: 1))
                    == "2024 · Show · 1 season")
        #expect(TitleCaption.of(TitleSummary(kind: .movie, tmdb: 3, title: "The Arrival")) == "Movie")
        #expect(TitleCaption.minutes(45) == "45 min")
        #expect(TitleCaption.minutes(120) == "2 h")
    }

    @Test func theLanguageIsOneTMDBReads() {
        #expect(TitleSource.language(of: Locale(identifier: "pt_BR"), country: "BR") == "pt-BR")
        #expect(TitleSource.language(of: Locale(identifier: "es_419"), country: "419") == "es")
        #expect(TitleSource.language(of: Locale(identifier: "fil_PH"), country: "PH") == "en")
    }
}
