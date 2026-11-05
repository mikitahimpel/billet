import Foundation
import Testing

@testable import Pet

@Suite("RoomLight")
struct RoomLightTests {
  @Test func oneSwitchGoesOnThenCosyThenOffThenOnAgain() {
    #expect(RoomLight.on.next == .cosy)
    #expect(RoomLight.cosy.next == .off)
    #expect(RoomLight.off.next == .on)
    #expect(RoomLight.standard == .on)
  }

  @Test func theRawValuesTheRoomSendsStayPut() {
    #expect(RoomLight.allCases.map(\.rawValue) == ["on", "cosy", "off"])
  }

  @Test func theSwitchSurvivesASaveAndLoad() {
    var play = PairPlay(device: "me")
    play.light(.cosy)
    let loaded = PairPlay(device: "me", saved: play.saved)
    #expect(loaded.roomLight == .cosy)
  }

  @Test func whatAnOlderReleaseSavedLoadsWithTheLightOn() throws {
    var named = PairPlay(device: "me")
    named.named("Mochi")
    var fields = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(named.saved)) as? [String: Any])
    fields["roomLight"] = nil
    let old = try JSONSerialization.data(withJSONObject: fields)
    let saved = try JSONDecoder().decode(PairPlay.Saved.self, from: old)
    let play = PairPlay(device: "me", saved: saved)
    #expect(play.roomLight == .on)
    #expect(play.catName == "Mochi")
  }
}
