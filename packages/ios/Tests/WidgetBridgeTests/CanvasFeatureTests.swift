import Foundation
import Testing

@testable import WidgetBridge

@Suite struct CanvasFeatureTests {
  @Test func promptsAreTheSameForTheSameDayAndAdvanceDayByDay() {
    #expect(DailyPrompt.question(on: "2026-11-10") == DailyPrompt.question(on: "2026-11-10"))
    #expect(DailyPrompt.question(on: "2026-11-10") != DailyPrompt.question(on: "2026-11-11"))
    #expect(DailyPrompt.doodle(on: "2026-11-10") != DailyPrompt.doodle(on: "2026-11-11"))
    let cycle = (0..<DailyPrompt.questions.count).map {
      DailyPrompt.index(
        "2026-11-\(String(format: "%02d", $0 + 1))", count: DailyPrompt.questions.count)
    }
    #expect(Set(cycle).count == DailyPrompt.questions.count)
  }

  @Test func aBrokenDayStillGivesAPrompt() {
    #expect(DailyPrompt.questions.contains(DailyPrompt.question(on: "nonsense")))
  }

  @Test func theCanvasPromptFollowsTheCardFlags() {
    var features = WidgetFeatures()
    #expect(
      DailyPrompt.canvasPrompt(features: features, day: "2026-11-10")
        == DailyPrompt.question(on: "2026-11-10"))
    features.set(.questionCard, on: false)
    #expect(DailyPrompt.canvasPrompt(features: features, day: "2026-11-10") == nil)
    features.set(.doodleCard, on: true)
    #expect(
      DailyPrompt.canvasPrompt(features: features, day: "2026-11-10")
        == DailyPrompt.doodle(on: "2026-11-10"))
  }

  @Test func theShortcutOpensTheCanvasOnlyWhenItsFlagIsOn() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var features = WidgetFeatures()
    func decide() -> Result<WidgetAction, WidgetActionRequest.Refusal> {
      WidgetActionRequest.decide(
        .openCanvas, at: .shortcut, features: features, snapshot: nil, pending: [], now: now,
        calendar: calendar)
    }
    #expect((try? decide().get()) != nil)
    features.set(.canvasShortcut, on: false)
    #expect(decide() == .failure(.off))
  }

  @Test func theDoodleCardStartsOffSoTheHomeScreenHasOneCard() {
    #expect(!WidgetFeature.doodleCard.defaultOn)
    #expect(WidgetFeature.questionCard.defaultOn)
  }
}
