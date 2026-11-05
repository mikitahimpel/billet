import Foundation
import Testing
@testable import Billet

/// Weeks start on Sunday here, as in the US locale: the featured set must still change on Monday.
private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
    c.firstWeekday = 1
    return c
}()

private func at(_ day: Int, _ hour: Int = 12, minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private func offers(_ seed: String = "L+M") -> ShopOffers { ShopOffers(pairSeed: seed, calendar: cal) }

@Suite struct ShopOffersTests {
    @Test func dealsAreTheSameAllDayAndChangeAtMidnight() {
        let morning = offers().deals(on: at(5, 0, minute: 1))
        #expect(morning == offers().deals(on: at(5, 23, minute: 59)))
        #expect(morning.count == ShopOffers.dealCount)
        #expect(Set(morning.map(\.itemID)).count == morning.count)
        // Over a week the draw changes at least once a day-pair; a fixed list would never change.
        let week = (5...11).map { offers().deals(on: at($0)).map(\.itemID) }
        #expect(Set(week).count > 1)
    }

    @Test func bothPartnersSeeTheSameDeals() {
        // The seed is the sorted monograms, so whoever holds the phone gets the same draw.
        let a = ShopOffers(pairSeed: ["M", "L"].sorted().joined(separator: "+"), calendar: cal)
        let b = ShopOffers(pairSeed: ["L", "M"].sorted().joined(separator: "+"), calendar: cal)
        #expect(a.deals(on: at(6)) == b.deals(on: at(6)))
        #expect(a.gift(on: at(6), owned: []) == b.gift(on: at(6), owned: []))
    }

    @Test func dealsAreOnlyFromThePoolAndPriceRoundsToFive() {
        let pool = Set(ShopOffers.dealPool.map(\.id))
        for day in 1...28 {
            for deal in offers().deals(on: at(day)) {
                #expect(pool.contains(deal.itemID))
                let item = Catalog.item(deal.itemID)!
                let price = deal.price(of: item)
                #expect(price % 5 == 0)
                #expect(price < item.price)
            }
        }
    }

    @Test func countdownsEndAtRealRotations() {
        let o = offers()
        #expect(o.nextDay(after: at(5, 21, minute: 30)) == at(6, 0))
        // 2026-11-05 is a Thursday; the featured set changes on Monday the 9th at midnight.
        #expect(o.nextWeek(after: at(5)) == at(9, 0))
        #expect(o.featured(on: at(5)).endsAt == at(9, 0))
        #expect(o.featured(on: at(5)) == o.featured(on: at(8, 23)))
        #expect(o.featured(on: at(9, 0, minute: 1)).id != o.featured(on: at(8)).id)

        var monday = cal
        monday.firstWeekday = 2
        let m = ShopOffers(pairSeed: "L+M", calendar: monday)
        #expect(m.featured(on: at(8, 23)) == o.featured(on: at(8, 23)))
        #expect(m.featured(on: at(9, 1)) == o.featured(on: at(9, 1)))
    }

    @Test func featuredPriceIsHalfTheMissingPiecesAndNilWhenOwned() {
        let offer = offers().featured(on: at(5))
        let sum = offer.itemIDs.compactMap(Catalog.item).reduce(0) { $0 + $1.price }
        let full = ShopOffers.price(of: offer, owned: [])!
        #expect(full.sum == sum)
        #expect(full.price == ShopOffers.roundToFive(Double(sum) * 0.5))

        let first = offer.itemIDs[0]
        let partial = ShopOffers.price(of: offer, owned: [first])!
        #expect(partial.sum == sum - Catalog.item(first)!.price)
        #expect(ShopOffers.price(of: offer, owned: Set(offer.itemIDs)) == nil)
    }

    @Test func giftNeverHandsOverAnOwnedItem() {
        let all = Set(ShopOffers.giftItems)
        for day in 1...60 {
            let date = cal.date(byAdding: .day, value: day, to: at(1))!
            switch offers().gift(on: date, owned: all) {
            case .coins(let amount): #expect(ShopOffers.giftCoins.contains(amount))
            case .item(let id): Issue.record("gave \(id), which is owned")
            }
        }
    }

    @Test func theGiftDayIsTheServersLocalDay() {
        #expect(ShopModel.localDay(at(5, 0, minute: 1), calendar: cal) == "2026-11-05")
        #expect(ShopModel.localDay(at(5, 23, minute: 59), calendar: cal) == "2026-11-05")
        #expect(ShopModel.localDay(at(6, 0, minute: 1), calendar: cal) == "2026-11-06")
    }

    @Test func everyItemHasARarityAndTheTopTwoShine() {
        #expect(Catalog.items.contains { $0.rarity == .legendary })
        #expect(ShopRarity.legendary.shines && ShopRarity.epic.shines)
        #expect(!ShopRarity.common.shines && !ShopRarity.rare.shines)
    }

    @Test func bundlesCostLessThanTheirPiecesAndOnlyTheMissingOnes() {
        #expect(Set(ShopOffers.bundles.map(\.id)).count == ShopOffers.bundles.count)
        for bundle in ShopOffers.bundles {
            #expect(bundle.itemIDs.allSatisfy { Catalog.item($0) != nil })
            let full = ShopOffers.price(of: bundle, owned: [])!
            #expect(full.price < full.sum)
            #expect(full.price % 5 == 0)

            let first = bundle.itemIDs[0]
            let partial = ShopOffers.price(of: bundle, owned: [first])!
            #expect(partial.sum == full.sum - Catalog.item(first)!.price)
            #expect(partial.price < full.price)
            #expect(ShopOffers.price(of: bundle, owned: Set(bundle.itemIDs)) == nil)
        }
    }

    @Test func noBundleRepeatsAFeaturedSet() {
        let featured = Set(ShopOffers.featuredSets.map { Set($0.itemIDs) })
        #expect(ShopOffers.bundles.allSatisfy { !featured.contains(Set($0.itemIDs)) })
    }

    @Test func collectionsCountOwnedPiecesAndCompleteOnlyWhenAllAreOwned() {
        for collection in Catalog.collections {
            #expect(collection.itemIDs.allSatisfy { Catalog.item($0) != nil })
            #expect(collection.bonus > 0)
            let allButLast = Set(collection.itemIDs.dropLast())
            #expect(collection.owned(of: allButLast) == collection.itemIDs.count - 1)
            #expect(!collection.isComplete(allButLast))
            #expect(collection.isComplete(Set(collection.itemIDs).union(["unrelated"])))
            #expect(collection.owned(of: ["unrelated"]) == 0)
        }
        #expect(Set(Catalog.collections.map(\.id)).count == Catalog.collections.count)
    }
}

/// The server's answers for (pair id, day), from `@billet/contracts-domain/shop`.
private struct OffersFixture: Decodable {
    struct Case: Decodable {
        struct Deal: Decodable {
            let item: String
            let discount: Double
            let price: Int
        }

        struct Gift: Decodable, Equatable {
            let _tag: String
            let coins: Int?
            let item: String?
        }

        let seed: String
        let day: String
        let deals: [Deal]
        let featured: String
        let gift: Gift
        let giftOwningGiftItems: Gift
    }

    let cases: [Case]

    static func load() throws -> OffersFixture {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../packages/contracts/fixtures/shop-offers.json").standardizedFileURL
        return try JSONDecoder().decode(OffersFixture.self, from: Data(contentsOf: url))
    }
}

@Suite struct ShopOffersFixtureTests {
    private func gift(_ reward: GiftReward) -> OffersFixture.Case.Gift {
        switch reward {
        case .coins(let coins): .init(_tag: "Coins", coins: coins, item: nil)
        case .item(let item): .init(_tag: "Item", coins: nil, item: item)
        }
    }

    /// The server prices the deals and opens the gift by the same rotation: a drift would show one price and charge
    /// another.
    @Test func theRotationsAreTheServers() throws {
        let fixture = try OffersFixture.load()
        #expect(!fixture.cases.isEmpty)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        for entry in fixture.cases {
            let parts = entry.day.split(separator: "-").compactMap { Int($0) }
            let noon = try #require(utc.date(from: DateComponents(
                year: parts[0], month: parts[1], day: parts[2], hour: 12)))
            let offers = ShopOffers(pairSeed: entry.seed, calendar: utc)
            let deals = offers.deals(on: noon)
            #expect(deals.map(\.itemID) == entry.deals.map(\.item), "\(entry.seed) \(entry.day)")
            #expect(deals.map(\.discount) == entry.deals.map(\.discount))
            #expect(deals.compactMap { deal in Catalog.item(deal.itemID).map { deal.price(of: $0) } } == entry.deals.map(\.price))
            #expect(offers.featured(on: noon).id == entry.featured, "\(entry.day)")
            #expect(gift(offers.gift(on: noon, owned: [])) == entry.gift, "\(entry.seed) \(entry.day)")
            #expect(gift(offers.gift(on: noon, owned: Set(ShopOffers.giftItems))) == entry.giftOwningGiftItems)
        }
    }
}
