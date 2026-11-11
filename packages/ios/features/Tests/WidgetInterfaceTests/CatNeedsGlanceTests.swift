import Foundation
import Testing

@testable import WidgetInterface

struct CatNeedsGlanceTests {
  let saved = Date(timeIntervalSince1970: 1_800_000_000)

  private func glance(
    full: Double = 0.8, rested: Double = 0.8, loved: Double = 0.8, playful: Double = 0.8
  ) -> CatNeedsGlance {
    CatNeedsGlance(
      full: full, rested: rested, loved: loved, playful: playful, lowBelow: 0.4, savedAt: saved)
  }

  @Test func contentWhileNothingIsLow() {
    #expect(glance().want(at: saved) == nil)
  }

  @Test func theLowestNeedBelowTheLineIsWhatShesWants() {
    #expect(glance(full: 0.3, playful: 0.35).want(at: saved) == .food)
    #expect(glance(loved: 0.2, playful: 0.35).want(at: saved) == .love)
    #expect(glance(playful: 0.39).want(at: saved) == .play)
    #expect(glance(rested: 0.1).want(at: saved) == .rest)
  }

  @Test func theLineItselfIsStillFine() {
    #expect(glance(full: 0.4).want(at: saved) == nil)
  }

  @Test func asleepWantsNothing() {
    #expect(glance(full: 0.1).want(at: saved, asleep: true) == nil)
  }

  @Test func anOldReadingSaysNothing() {
    let low = glance(full: 0.1)
    #expect(low.want(at: saved.addingTimeInterval(CatNeedsGlance.freshFor - 1)) == .food)
    #expect(low.want(at: saved.addingTimeInterval(CatNeedsGlance.freshFor)) == nil)
    #expect(low.want(at: saved.addingTimeInterval(-1)) == nil)
  }

  @Test func aMealFromTheWidgetEndsHunger() {
    let hungry = glance(full: 0.1)
    let meal = saved.addingTimeInterval(60)
    let later = saved.addingTimeInterval(120)
    #expect(hungry.want(at: later, fedAt: meal) == nil)
    #expect(hungry.want(at: later, fedAt: saved.addingTimeInterval(-60)) == .food)
    #expect(hungry.want(at: saved.addingTimeInterval(30), fedAt: meal) == .food)
  }

  @Test func aPetFromTheWidgetLiftsLoveByAStroke() {
    let lonely = glance(loved: 0.3)
    let later = saved.addingTimeInterval(120)
    #expect(lonely.want(at: later, pettedAt: saved.addingTimeInterval(60)) == nil)
    #expect(glance(loved: 0.1).want(at: later, pettedAt: saved.addingTimeInterval(60)) == .love)
  }

  @Test func theAppWritesOnlyWhenTheAnswerOrTheAgeChanges() {
    let old = glance(full: 0.3)
    var drifted = glance(full: 0.25)
    drifted.savedAt = saved.addingTimeInterval(60)
    #expect(!drifted.differsForWidgets(from: old))
    var fed = glance(full: 0.9)
    fed.savedAt = saved.addingTimeInterval(60)
    #expect(fed.differsForWidgets(from: old))
    var stale = glance(full: 0.3)
    stale.savedAt = saved.addingTimeInterval(CatNeedsGlance.freshFor)
    #expect(stale.differsForWidgets(from: old))
    #expect(old.differsForWidgets(from: nil))
  }

  @Test func activityFromBeforeMealsStillReads() throws {
    let json = #"{"pendingPets":2,"ideaID":4}"#
    let activity = try JSONDecoder().decode(WidgetActivity.self, from: Data(json.utf8))
    #expect(activity.pendingPets == 2)
    #expect(activity.ideaID == 4)
    #expect(activity.pendingFeeds == 0)
    #expect(activity.lastFed == nil)
  }

  @Test func mealsQueueUntilTheAppTakesThem() {
    var activity = WidgetActivity()
    activity.feed(at: saved)
    activity.feed(at: saved)
    #expect(activity.lastFed == saved)
    #expect(activity.takePendingFeeds() == 2)
    #expect(activity.takePendingFeeds() == 0)
    #expect(activity.lastFed == saved)
  }
}
