import Foundation
import DrawInterface
import MoodInterface
import WidgetInterface
import Testing
import Wire

@MainActor
struct FamilyLogicTests {
    let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now

    private func snapshot(night: Bool = false, purring: Bool = false, mood: PartnerMood? = nil,
                          age: TimeInterval = 600) -> OurioSnapshot {
        var s = OurioSnapshot.sample(now: noon)
        s.isNight = night
        s.isPurring = purring
        s.partnerMood = mood.map { MoodCheckIn(mood: $0, date: noon.addingTimeInterval(-age)) }
        return s
    }

    private func drawing(age: TimeInterval, strokes: Bool = true) -> LatestDrawing {
        LatestDrawing(
            noteID: "n", seq: 1, sentAt: noon.addingTimeInterval(-age),
            compact: CompactStrokes(strokes: strokes
                ? [CompactStroke(color: "#7B4FE0", width: 32, points: [0, 0, 100, 100])] : []),
            paper: nil)
    }

    @Test func poseFollowsWhatHappened() {
        #expect(MochiPose.pose(snapshot(purring: true), drawing: nil) == .purring)
        #expect(MochiPose.pose(snapshot(night: true, purring: true), drawing: nil) == .purring)
        #expect(MochiPose.pose(snapshot(night: true, mood: .missing), drawing: nil) == .asleep)
        #expect(MochiPose.pose(snapshot(mood: .missing), drawing: nil) == .waiting)
        #expect(MochiPose.pose(snapshot(mood: .happy), drawing: nil) == .chirpy)
        #expect(MochiPose.pose(snapshot(mood: .sleepy), drawing: nil) == .napping)
        #expect(MochiPose.pose(snapshot(mood: .busy), drawing: nil) == .quiet)
        #expect(MochiPose.pose(snapshot(), drawing: nil) == .idle)
    }

    @Test func aStaleCheckInIsNotNews() {
        #expect(MochiPose.pose(snapshot(mood: .missing, age: 4 * 3600), drawing: nil) == .idle)
    }

    @Test func aFreshDrawingKeepsHerWaiting() {
        let s = snapshot(mood: .happy)
        #expect(MochiPose.pose(s, drawing: drawing(age: 300)) == .waiting)
        #expect(MochiPose.pose(s, drawing: drawing(age: 3 * 86_400)) == .chirpy)
        #expect(MochiPose.pose(s, drawing: drawing(age: 300, strokes: false)) == .chirpy)
    }

    @Test func theNewerOfDrawingAndMoodWins() {
        let s = snapshot(mood: .missing, age: 1200)
        if case .drawing = PartnerNews.latest(s, drawing: drawing(age: 600)) {} else { Issue.record("drawing is newer") }
        if case .mood = PartnerNews.latest(s, drawing: drawing(age: 1800)) {} else { Issue.record("mood is newer") }
    }

    @Test func aDrawingFromTomorrowIsIgnored() {
        #expect(PartnerNews.latest(snapshot(), drawing: drawing(age: -60)) == nil)
    }

    @Test func streakProgressRunsBetweenMilestones() {
        let today = Calendar.current.startOfDay(for: noon)
        let glance = StreakGlance(LoveStreak(count: 10, lastDay: today, best: 10), on: noon)
        #expect(glance.next == 14)
        #expect(glance.toGo == 4)
        #expect(abs(glance.progress - 3.0 / 7.0) < 0.001)
        #expect(glance.caption == "4 to 14")
    }

    @Test func streakStatesReadAsWords() {
        let today = Calendar.current.startOfDay(for: noon)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        #expect(StreakGlance(LoveStreak(count: 5, lastDay: yesterday, best: 5), on: noon).isAtRisk)
        #expect(StreakGlance(LoveStreak(count: 5, lastDay: yesterday, best: 5), on: noon).caption == "Keep it today")
        #expect(StreakGlance(LoveStreak(), on: noon).caption == "Start a streak today")
        #expect(StreakGlance(LoveStreak(count: 400, lastDay: today, best: 400), on: noon).caption == "Best streak yet")
    }

    @Test func coinsCaptionPrefersTheWishlist() {
        #expect(CoinsGlance(Wallet(coins: 0)).caption == "Earn coins by caring")
        #expect(CoinsGlance(Wallet(coins: 5)).caption == "Treat the room")
        #expect(CoinsGlance(Wallet(coins: 5, wishlist: ["a"])).caption == "1 on your wishlist")
        #expect(CoinsGlance(Wallet(progress: 3)).progress == 1)
    }

    @Test func timelineIsSparse() {
        let pet = noon.addingTimeInterval(-30)
        let dates = FamilyTimeline.entryDates(
            from: noon, activity: WidgetActivity(lastPet: pet, pendingPets: 1), moods: [:], drawing: drawing(age: 3600))
        #expect(dates.first == noon)
        #expect(dates.contains(pet.addingTimeInterval(WidgetActivity.purrLength)))
        #expect(dates.count <= 8)
        for (a, b) in zip(dates, dates.dropFirst()) {
            #expect(b.timeIntervalSince(a) >= FamilyTimeline.minimumGap || b == pet.addingTimeInterval(WidgetActivity.purrLength))
        }
    }

    @Test func aDrawingStopsBeingNewsInTheTimeline() {
        let sent = noon.addingTimeInterval(-3600)
        let dates = FamilyTimeline.entryDates(from: noon, activity: WidgetActivity(), moods: [:], drawing: drawing(age: 3600))
        #expect(dates.contains(sent.addingTimeInterval(PartnerNews.drawingNews)))
    }

    @Test func theHugShowsSentOnlyForTodaysMissingYou() {
        var s = snapshot()
        #expect(!HugState.sent(s))
        s.myMood = MoodCheckIn(mood: .missing, date: noon.addingTimeInterval(-600))
        #expect(HugState.sent(s))
        s.myMood = MoodCheckIn(mood: .happy, date: noon.addingTimeInterval(-600))
        #expect(!HugState.sent(s))
        s.myMood = MoodCheckIn(mood: .missing, date: noon.addingTimeInterval(-2 * 86_400))
        #expect(!HugState.sent(s))
    }

    @Test func everyStateHasADistinctLockGlyph() {
        let poses: [MochiPose] = [.purring, .asleep, .waiting, .chirpy, .napping, .quiet, .idle]
        #expect(Set(poses.map(\.lockSymbol)).count == poses.count)
        #expect(Set(PartnerMood.allCases.map(\.lockSymbol)).count == PartnerMood.allCases.count)
    }

    @Test func sentLabelsStayTrueUntilTheNextReload() {
        let cal = Calendar.current
        let mood = MoodCheckIn(mood: .happy, date: noon.addingTimeInterval(-600))
        let yesterday = MoodCheckIn(mood: .happy, date: cal.date(byAdding: .day, value: -1, to: noon) ?? noon)
        #expect(PartnerNews.mood(mood).sentLabel(relativeTo: noon) != "Yesterday")
        #expect(PartnerNews.mood(yesterday).sentLabel(relativeTo: noon) == "Yesterday")
        #expect(!PartnerNews.mood(mood).sentLabel(relativeTo: noon).contains("ago"))
    }
}
