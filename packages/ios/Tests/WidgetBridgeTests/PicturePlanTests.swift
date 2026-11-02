import Foundation
import Pet
import Testing

@testable import WidgetBridge

@Suite struct PicturePlanTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(
      from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
  }

  private func snapshot(
    at now: Date, treat: WidgetSnapshot.Treat = .neither, streak: Int = 0, here: Bool = false,
    since: Date? = nil, sent: Date? = nil
  ) -> WidgetSnapshot {
    WidgetSnapshot(
      treat: treat, treatDay: TreatDay.key(for: now, calendar: calendar), streak: streak,
      partnerHere: here, pairedSince: since, lastSentAt: sent, updatedAt: now)
  }

  private func only(_ feature: WidgetFeature) -> WidgetFeatures {
    var features = WidgetFeatures()
    for other in WidgetFeature.allCases { features.set(other, on: other == feature) }
    return features
  }

  private func inputs(
    _ features: WidgetFeatures, _ snapshot: WidgetSnapshot?, drawing: Bool = true
  ) -> PicturePlan.Inputs {
    .init(features: features, snapshot: snapshot, hasDrawing: drawing, calendar: calendar)
  }

  @Test func eachPictureAppearsOnlyWhenItsFlagIsOn() {
    let now = date(10, 12)
    let full = snapshot(at: now, streak: 3, since: date(1, 9), sent: date(1, 9))
    for mode in PictureMode.allCases {
      let on = PicturePlan.available(inputs(only(mode.feature), full), at: now)
      #expect(on == [mode], "\(mode)")
      var off = WidgetFeatures()
      off.set(mode.feature, on: false)
      #expect(!PicturePlan.available(inputs(off, full), at: now).contains(mode), "\(mode)")
    }
  }

  @Test func everyFlagOffMeansAllOff() {
    var features = WidgetFeatures()
    for mode in PictureMode.allCases { features.set(mode.feature, on: false) }
    #expect(PicturePlan.choice(inputs(features, nil), at: date(10, 12)) == .allOff)
  }

  @Test func aPictureWithNothingToShowIsSkipped() {
    let now = date(10, 12)
    let features = only(.partnerDrawing)
    #expect(PicturePlan.choice(inputs(features, nil, drawing: false), at: now) == .nothingYet)
    #expect(PicturePlan.choice(inputs(only(.streak), snapshot(at: now)), at: now) == .nothingYet)
    #expect(
      PicturePlan.choice(inputs(only(.daysTogether), snapshot(at: now)), at: now) == .nothingYet)
    #expect(PicturePlan.choice(inputs(only(.catMood), nil), at: now) == .nothingYet)
  }

  @Test func nudgeWaitsForTwoQuietDays() {
    let features = only(.nudge)
    let since = date(1, 9)
    let now = date(10, 12)
    let recent = snapshot(at: now, since: since, sent: date(9, 20))
    let old = snapshot(at: now, since: since, sent: date(7, 20))
    let never = snapshot(at: now, since: since)
    #expect(PicturePlan.available(inputs(features, recent), at: now).isEmpty)
    #expect(PicturePlan.available(inputs(features, old), at: now) == [.nudge])
    #expect(PicturePlan.available(inputs(features, never), at: now) == [.nudge])
    #expect(PicturePlan.available(inputs(features, snapshot(at: now)), at: now).isEmpty)
  }

  @Test func withoutRotationTheMostPressingPictureStays() {
    let now = date(10, 12)
    var features = WidgetFeatures()
    features.set(.rotatePictures, on: false)
    let full = snapshot(at: now, streak: 3, since: date(1, 9), sent: date(1, 9))
    #expect(PicturePlan.choice(inputs(features, full), at: now) == .picture(.nudge))
    features.set(.nudge, on: false)
    #expect(PicturePlan.choice(inputs(features, full), at: now) == .picture(.partnerDrawing))
  }

  @Test func rotationTakesTurnsByTheClock() {
    var features = only(.rotatePictures)
    features.set(.catMood, on: true)
    features.set(.timeOfDay, on: true)
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let snap = snapshot(at: start)
    let list = PicturePlan.available(inputs(features, snap), at: start)
    #expect(list == [.catMood, .timeOfDay])
    var seen: [PictureMode] = []
    for turn in 0..<4 {
      let at = start.addingTimeInterval(Double(turn) * PicturePlan.slot + 5)
      guard case .picture(let mode) = PicturePlan.choice(inputs(features, snapshot(at: at)), at: at)
      else {
        Issue.record("no picture")
        return
      }
      seen.append(mode)
    }
    #expect(seen == [.catMood, .timeOfDay, .catMood, .timeOfDay])
  }

  @Test func rotationHoldsStillWithOnePicture() {
    let now = date(10, 12)
    var features = only(.catMood)
    features.set(.rotatePictures, on: true)
    for step in 0..<3 {
      let at = now.addingTimeInterval(Double(step) * PicturePlan.slot)
      #expect(
        PicturePlan.choice(inputs(features, snapshot(at: at)), at: at) == .picture(.catMood))
    }
  }

  @Test func datesStartNowStayInsideTheHorizonAndFollowTheStep() {
    let now = date(10, 12, 7)
    let rotating = PicturePlan.dates(inputs(only(.rotatePictures), nil), from: now)
    #expect(rotating.first == now)
    #expect(rotating.dropFirst().first == date(10, 12, 15))
    #expect(rotating.allSatisfy { $0 < now.addingTimeInterval(PicturePlan.horizon) })
    let still = PicturePlan.dates(inputs(only(.catMood), nil), from: now)
    #expect(still.dropFirst().first == date(10, 13))
  }

  @Test(arguments: [
    (4, DayPhase.night), (5, .dawn), (8, .day), (16, .day), (17, .dusk), (21, .night),
  ])
  func dayPhaseByHour(_ hour: Int, _ phase: DayPhase) {
    #expect(DayPhase(hour: hour) == phase)
  }
}

@Suite struct PictureCaptionTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private func at(_ day: Int, _ hour: Int) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
  }

  private func snapshot(here: Bool = false) -> WidgetSnapshot {
    WidgetSnapshot(
      catName: "Mochi", treat: .fed, treatDay: "2026-11-10", streak: 7, partnerHere: here,
      pairedSince: at(1, 9), lastSentAt: at(7, 9), updatedAt: at(10, 12))
  }

  @Test func everyModeHasWordsAndASymbolWithOrWithoutData() {
    for mode in PictureMode.allCases {
      for snap in [nil, snapshot()] {
        let caption = PictureCaption.make(mode, snapshot: snap, now: at(10, 12), calendar: calendar)
        #expect(!caption.headline.isEmpty && !caption.detail.isEmpty && !caption.symbol.isEmpty)
      }
    }
  }

  @Test func numbersAreTheRealCounts() {
    let streak = PictureCaption.make(
      .streak, snapshot: snapshot(), now: at(10, 12), calendar: calendar)
    #expect(streak.number == 7)
    let days = PictureCaption.make(
      .daysTogether, snapshot: snapshot(), now: at(10, 12), calendar: calendar)
    #expect(days.number == 10)
  }

  @Test func windowFollowsPresence() {
    let here = PictureCaption.make(
      .partnerWindow, snapshot: snapshot(here: true), now: at(10, 12), calendar: calendar)
    let away = PictureCaption.make(
      .partnerWindow, snapshot: snapshot(here: false), now: at(10, 12), calendar: calendar)
    #expect(here.headline == "They're here")
    #expect(away.headline == "Window's dark")
  }

  @Test func nudgeCountsQuietDaysAndMoodUsesTheCatsName() {
    let nudge = PictureCaption.make(
      .nudge, snapshot: snapshot(), now: at(10, 12), calendar: calendar)
    #expect(nudge.detail.contains("3 days"))
    let mood = PictureCaption.make(
      .catMood, snapshot: snapshot(), now: at(10, 12), calendar: calendar)
    #expect(mood.headline == "Mochi")
  }

  @Test func timeOfDayFollowsTheHour() {
    let night = PictureCaption.make(.timeOfDay, snapshot: nil, now: at(10, 23), calendar: calendar)
    #expect(night.headline == "Night")
    let morning = PictureCaption.make(.timeOfDay, snapshot: nil, now: at(10, 6), calendar: calendar)
    #expect(morning.headline == "Morning")
  }
}
