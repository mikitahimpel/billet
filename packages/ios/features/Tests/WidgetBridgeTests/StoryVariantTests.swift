import Testing

@testable import WidgetBridge

@Suite struct StoryVariantTests {
  @Test func noAnswerMeansOff() {
    #expect(StoryVariant.resolved(remote: RemoteFlags()) == .off)
    #expect(!StoryVariant.resolved(remote: RemoteFlags()).isOn)
  }

  @Test func theServerTurnsItOn() {
    let remote = RemoteFlags(assignments: ["story": "on"])
    #expect(StoryVariant.resolved(remote: remote) == .on)
  }

  @Test func aVariantThisBuildLacksIsIgnored() {
    let remote = RemoteFlags(assignments: ["story": "season-two"])
    #expect(StoryVariant.resolved(remote: remote) == .off)
  }
}
