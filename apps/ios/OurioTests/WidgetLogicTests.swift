import Foundation
import Testing
import Wire
@testable import Billet

private let cal = Calendar.current
private let noon = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!

private func snapshot(next: Int? = 18, partnerMood: MoodCheckIn? = nil, planned: Date? = nil,
                      partnerAddedToday: Bool = false, openCount: Int = 2) -> OurioSnapshot {
    OurioSnapshot(
        date: noon, viewer: "L", partner: "M", daysTogether: 127,
        next: next.map { .init(title: "Anniversary", icon: .init(symbol: "heart.fill", tint: .blush),
                               date: cal.date(byAdding: .day, value: $0, to: noon)!, daysLeft: $0) },
        partnerMood: partnerMood, myMood: nil,
        list: .init(id: UUID(), title: "Groceries", icon: ListKind.groceries.icon, items: [], openCount: openCount,
                    partnerAddedToday: partnerAddedToday),
        planned: planned.map { .init(id: UUID(), title: "Picnic", date: $0, hint: nil, isToday: cal.isDate($0, inSameDayAs: noon)) },
        idea: nil, moment: nil, isPurring: false, isNight: false)
}

@Suite struct SmartSlotTests {
    @Test func defaultsToTogether() {
        #expect(snapshot().smartModule == .us)
    }

    @Test func dateTonightBeatsEverything() {
        let s = snapshot(next: 1, partnerMood: MoodCheckIn(mood: .missing, date: noon.addingTimeInterval(-600)),
                         planned: noon.addingTimeInterval(6 * 3600), partnerAddedToday: true)
        #expect(s.smartModule == .date)
    }

    @Test func dateLaterThisWeekDoesNotTakeTheSlot() {
        #expect(snapshot(planned: noon.addingTimeInterval(3 * 86_400)).smartModule == .us)
    }

    @Test func freshCheckInShowsMood() {
        let s = snapshot(partnerMood: MoodCheckIn(mood: .sleepy, date: noon.addingTimeInterval(-3600)))
        #expect(s.smartModule == .mood)
    }

    @Test func checkInStopsBeingNewsAfterThreeHours() {
        let s = snapshot(partnerMood: MoodCheckIn(mood: .sleepy, date: noon.addingTimeInterval(-3 * 3600 - 1)))
        #expect(s.freshPartnerMood == nil)
        #expect(s.smartModule == .us)
    }

    @Test func eventInThreeDaysIsCountdown() {
        #expect(snapshot(next: 3, partnerAddedToday: true).smartModule == .us)
    }

    @Test func partnerAddedItemsShowList() {
        #expect(snapshot(partnerAddedToday: true).smartModule == .list)
        #expect(snapshot(partnerAddedToday: true, openCount: 0).smartModule == .us)
    }
}

@Suite struct WidgetTimelineTests {
    @Test func entriesAtPurrEndNightAndMidnight() {
        var activity = WidgetActivity()
        activity.pet(at: noon)
        let dates = WidgetTimeline.entryDates(from: noon, activity: activity, moods: [:])
        let hours = dates.map { cal.component(.hour, from: $0) }
        #expect(dates.first == noon)
        #expect(dates.contains(noon.addingTimeInterval(WidgetActivity.purrLength)))
        #expect(hours.contains(20) && hours.contains(0) && hours.contains(7))
        #expect(dates == dates.sorted())
        #expect(dates.allSatisfy { $0 <= noon.addingTimeInterval(24 * 3600) })
    }

    @Test func entryWhenCheckInExpires() {
        let check = MoodCheckIn(mood: .happy, date: noon.addingTimeInterval(-600))
        let dates = WidgetTimeline.entryDates(from: noon, activity: WidgetActivity(), moods: ["M": check])
        #expect(dates.contains(check.date.addingTimeInterval(OurioSnapshot.moodNews)))
    }

    @Test func nightRunsFromEightToSeven() {
        #expect(OurioSnapshot.isNight(cal.date(bySettingHour: 21, minute: 0, second: 0, of: noon)!))
        #expect(OurioSnapshot.isNight(cal.date(bySettingHour: 6, minute: 59, second: 0, of: noon)!))
        #expect(!OurioSnapshot.isNight(cal.date(bySettingHour: 7, minute: 0, second: 0, of: noon)!))
    }
}

@Suite struct WidgetActivityTests {
    @Test func petsWaitForTheApp() {
        var activity = WidgetActivity()
        activity.pet(at: noon)
        activity.pet(at: noon.addingTimeInterval(5))
        #expect(activity.isPurring(at: noon.addingTimeInterval(30)))
        #expect(!activity.isPurring(at: noon.addingTimeInterval(70)))
        #expect(activity.takePendingPets() == 2)
        #expect(activity.takePendingPets() == 0)
    }
}

@Suite struct CoupleTests {
    @Test func starterIsDayOne() {
        #expect(Couple.starter(now: noon).daysTogether(on: noon) == 1)
    }

    @Test func otherPartner() {
        var couple = Couple.starter(now: noon)
        #expect(couple.other == "M")
        couple.viewer = "M"
        #expect(couple.other == "L")
    }
}

@Suite struct DeepLinkTests {
    @Test(arguments: [DeepLink.room, .moments, .us, .calendar, .dates, .list(UUID()), .shopInk("ink-rose")])
    func roundTrips(_ link: DeepLink) {
        #expect(DeepLink(url: link.url) == link)
    }

    @Test func rejectsForeignURLs() {
        #expect(DeepLink(url: URL(string: "https://room")!) == nil)
        #expect(DeepLink(url: URL(string: "ourio://us/list/not-a-uuid")!) == nil)
        #expect(DeepLink(url: URL(string: "ourio://shop")!) == nil)
        #expect(DeepLink(url: URL(string: "ourio://shop/ink")!) == nil)
    }

    @Test func aShopInkLinkOpensTheShopAtThatInk() {
        #expect(DeepLink.shopInk("ink-rose").url.absoluteString == "ourio://shop/ink/ink-rose")
        let state = HomeState(stores: .live())
        state.open(.shopInk("ink-rose"))
        #expect(state.tab == .shop)
        #expect(state.shopFocus == .ink("ink-rose"))
    }
}

/// A store file of its own under the app group, removed after the test.
func scratchFile(_ name: String) -> String { "Tests/\(UUID().uuidString)-\(name)" }

func removeScratch(_ path: String) {
    SharedFile.flush()
    try? FileManager.default.removeItem(at: SharedFile.url(path))
}

@Suite struct WalletTests {
    @Test func aFreshWalletHasNoCoinsUntilTheServerSays() {
        let path = scratchFile("wallet.json")
        defer { removeScratch(path) }
        #expect(WalletStore(file: path).wallet == Wallet())
        #expect(Wallet().coins == 0)
        #expect(!Wallet().isSynced)
    }

    @Test func roundTripsThroughTheSharedFile() {
        let path = scratchFile("wallet.json")
        defer { removeScratch(path) }
        let store = WalletStore(file: path)
        store.update {
            $0.coins = 42
            $0.level = 7
            $0.owned.insert("tower")
            $0.gifted.insert("yarn")
        }
        // A pending write is visible to this process before it lands, and on disk after a flush.
        #expect(WalletStore(file: path).wallet == store.wallet)
        SharedFile.flush()
        let data = try? Data(contentsOf: SharedFile.url(path))
        #expect(data.flatMap { try? JSONDecoder().decode(Wallet.self, from: $0) } == store.wallet)
    }

    @Test func anUnreadableFileIsKeptAsideNotOverwritten() throws {
        let path = scratchFile("wallet.json")
        let aside = SharedFile.url(path).appendingPathExtension("unreadable")
        defer {
            removeScratch(path)
            try? FileManager.default.removeItem(at: aside)
        }
        let file = SharedFile.url(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"coins": 9000, "#.utf8).write(to: file)
        #expect(WalletStore(file: path).wallet == Wallet())
        #expect(try Data(contentsOf: aside) == Data(#"{"coins": 9000, "#.utf8))
    }

    @Test func aTickIsPaidInThePairsRoomNotByThePhone() {
        let usPath = scratchFile("us.json")
        defer { removeScratch(usPath) }
        var earned: [EarnEvent] = []
        let us = UsStore(file: usPath) { earned.append($0) }
        let watch = us.lists.first { $0.kind == .watch }!.id
        us.addItem("Paddington", to: watch, author: "L")
        us.setItem(us.list(watch)!.items[0].id, in: watch, done: true)
        #expect(us.list(watch)!.items[0].done != nil)
        #expect(earned.isEmpty)
    }
}

@Suite struct CalendarTests {
    private func store(_ events: [UsEvent]) -> (UsStore, String) {
        let path = scratchFile("us.json")
        let us = UsStore(file: path)
        events.forEach(us.upsertEvent)
        return (us, path)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
    }

    private let longAgo = cal.date(from: DateComponents(year: 1990, month: 1, day: 1))!

    @Test func leapDayComesBackInLeapYears() {
        let birthday = UsEvent(title: "Birthday", icon: UsGlyph.palette[2], date: day(2024, 2, 29), yearly: true)
        let (us, path) = store([birthday])
        defer { removeScratch(path) }
        let next = { (now: Date) in us.upcoming(togetherSince: longAgo, from: now).first { $0.source == .event(birthday.id) }?.date }
        #expect(next(day(2025, 3, 1)).map { cal.dateComponents([.year, .month, .day], from: $0) } == DateComponents(year: 2026, month: 2, day: 28))
        #expect(next(day(2027, 3, 1)).map { cal.dateComponents([.year, .month, .day], from: $0) } == DateComponents(year: 2028, month: 2, day: 29))
    }

    @Test func monthShowsPastAndFutureYears() {
        let birthday = UsEvent(title: "Birthday", icon: UsGlyph.palette[2], date: day(2020, 3, 14), yearly: true)
        let trip = UsEvent(title: "Trip", icon: UsGlyph.palette[3], date: day(2025, 3, 2))
        let (us, path) = store([birthday, trip])
        defer { removeScratch(path) }
        let month = { (year: Int) in
            us.occurrences(togetherSince: longAgo, in: cal.dateInterval(of: .month, for: day(year, 3, 1))!).map(\.title)
        }
        #expect(month(2025) == ["Trip", "Birthday"])
        #expect(month(2031) == ["Birthday"])
        #expect(month(2019) == [])
        #expect(us.occurrences(togetherSince: longAgo, in: cal.dateInterval(of: .month, for: day(2025, 4, 1))!).isEmpty)
    }

    @Test func monthIncludesMilestones() {
        let (us, path) = store([])
        defer { removeScratch(path) }
        let start = day(2026, 1, 1)
        let titles = us.occurrences(togetherSince: start, in: cal.dateInterval(of: .month, for: day(2026, 4, 1))!).map(\.title)
        #expect(titles == ["3 months together", "100 days together"])
    }
}
