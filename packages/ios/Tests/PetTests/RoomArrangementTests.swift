import Foundation
import Testing

@testable import Pet

@Suite("RoomArrangement")
struct RoomArrangementTests {
  @Test func aSpotIsSentAsXDepthAndTurn() throws {
    let data = try JSONEncoder().encode(PieceSpot(x: 3, z: 5.5, yaw: 1.5))
    #expect(String(decoding: data, as: UTF8.self) == "[3,5.5,1.5]")
    #expect(
      try JSONDecoder().decode(PieceSpot.self, from: data) == PieceSpot(x: 3, z: 5.5, yaw: 1.5))
  }

  @Test func eachRoomKeepsItsLastArrangement() {
    var play = PairPlay(device: "me")
    play.arrange(
      RoomArrangement(room: "windowSeat.cosyNook", spots: ["pouf": .init(x: 3, z: 5, yaw: 0)]))
    play.arrange(
      RoomArrangement(room: "windowSeat.retroDen", spots: ["rug": .init(x: 2, z: 3, yaw: 1)]))
    play.arrange(RoomArrangement(room: "windowSeat.cosyNook", spots: [:]))
    #expect(play.arrangements["windowSeat.cosyNook"] == [:])
    #expect(play.arrangements["windowSeat.retroDen"]?["rug"] == PieceSpot(x: 2, z: 3, yaw: 1))
  }

  @Test func arrangementsSurviveASaveAndLoad() {
    var play = PairPlay(device: "me")
    play.arrange(
      RoomArrangement(room: "windowSeat.cosyNook", spots: ["pouf": .init(x: 3, z: 5, yaw: 0)]))
    let loaded = PairPlay(device: "me", saved: play.saved)
    #expect(loaded.arrangements == play.arrangements)
  }

  @Test func whatAnOlderReleaseSavedLoadsWithEveryRoomAsItCame() throws {
    var fields = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(PairPlay(device: "me").saved))
        as? [String: Any])
    fields["arrangements"] = nil
    let old = try JSONSerialization.data(withJSONObject: fields)
    let play = PairPlay(
      device: "me", saved: try JSONDecoder().decode(PairPlay.Saved.self, from: old))
    #expect(play.arrangements.isEmpty)
  }
}
