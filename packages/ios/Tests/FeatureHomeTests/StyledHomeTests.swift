import Foundation
import Testing

@testable import FeatureHome

@MainActor @Suite struct StyledHomeTests {
  @Test func theCaptionSaysWhoTheNoteIsFromAndWhen() {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let caption = StyledHome.caption(for: now.addingTimeInterval(-300), now: now)
    #expect(caption.hasPrefix("A note from your partner · "))
    #expect(caption.contains("5"))
  }

  @Test func aNoteFromAClockThatRunsFastReadsAsNow() {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let ahead = StyledHome.caption(for: now.addingTimeInterval(120), now: now)
    #expect(ahead == StyledHome.caption(for: now, now: now))
  }
}
