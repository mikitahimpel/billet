import Foundation
import Pet
import Testing
@testable import Billet

@Suite struct HomecomingLineTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()
    private static let locale = Locale(identifier: "en_GB")
    /// Tuesday 10 November 2026, 18:00.
    private static let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 18))!

    static func event(_ kind: LifeEvent.Kind, day: Int = 10, hour: Int, minute: Int = 0) -> LifeEvent {
        let at = calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        return LifeEvent(id: UUID(), kind: kind, by: "user-them", at: at)
    }

    private static func line(_ care: [LifeEvent]) -> String? {
        HomecomingLine(care, partner: "Ilya", cat: "Mochi", now: now, calendar: calendar, locale: locale)?.text
    }

    @Test func aMealIsTheNewsOverPetsAndGames() {
        let care = [Self.event(.pet, hour: 8), Self.event(.feed, hour: 9, minute: 5), Self.event(.play, hour: 12)]
        #expect(Self.line(care) == "Ilya fed Mochi at 09:05")
    }

    @Test func theLatestOfTheKindIsTold() {
        #expect(Self.line([Self.event(.pet, hour: 8), Self.event(.pet, hour: 14)]) == "Ilya petted Mochi at 14:00")
    }

    @Test func yesterdayAndEarlierSayWhen() {
        #expect(Self.line([Self.event(.play, day: 9, hour: 22)]) == "Ilya played with Mochi yesterday at 22:00")
        #expect(Self.line([Self.event(.sleep, day: 8, hour: 23)]) == "Ilya put Mochi to bed on Sunday")
    }

    @Test(arguments: [[LifeEvent](), [HomecomingLineTests.event(.shoo, hour: 9)]])
    func nothingWorthTellingIsNoLine(care: [LifeEvent]) {
        #expect(Self.line(care) == nil)
    }
}
