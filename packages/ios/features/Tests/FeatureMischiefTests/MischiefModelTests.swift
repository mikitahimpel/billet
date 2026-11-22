import Foundation
import MischiefInterface
import Testing
import Wire

@testable import FeatureMischief

@MainActor
struct MischiefModelTests {
  static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

  /// A phone for `me`, its journal calls and what the room was told.
  @MainActor final class Phone {
    var recorded: [CatEvent] = []
    var hints: [MischiefHint] = []
    var played: [MischiefModel.Played] = []
    var saved: [MischiefLedger] = []
    var now = MischiefModelTests.t0
    var nextId = 0
  }

  static func model(
    _ phone: Phone, me: String = "mia", partner: String = "leo", paired: Bool = true
  )
    -> MischiefModel
  {
    let model = MischiefModel(
      pair: { paired ? .init(me: me, partner: partner) : nil },
      storage: .init(load: { nil }, save: { phone.saved.append($0) }), now: { phone.now },
      record: { events in
        events.map { event in
          phone.recorded.append(event)
          phone.nextId += 1
          return IdempotencyKey("e\(phone.nextId)")
        }
      },
      hint: { phone.hints.append($0) }, played: { phone.played.append($0) })
    model.roomSpots(
      MischiefSpotMap([
        .basket: .init(x: 0, z: 0), .sofa: .init(x: 0.2, z: 0), .sill: .init(x: 0.4, z: 0),
        .tree: .init(x: 0.7, z: 0), .crate: .init(x: 1.2, z: 0),
      ]))
    return model
  }

  static func partnerHid(_ model: MischiefModel, spot: String = "basket", line: String? = "boo") {
    model.receive(
      CatEntry(
        seq: 1, id: IdempotencyKey("h1"), by: UserId("leo"), at: MischiefLedgerTests.ms(t0),
        event: .mouseHidden(spot: spot, line: line)))
  }

  @Test func hidingSendsTheEventAndCountsItAtOnce() {
    let phone = Phone()
    let model = Self.model(phone)
    model.send(.opened)
    model.send(.picked(.sofa))
    model.send(.wrote("find me"))
    model.send(.submitted)
    #expect(phone.recorded == [.mouseHidden(spot: "sofa", line: "find me")])
    #expect(phone.played == [.hid])
    #expect(model.mine?.spot == .sofa)
    #expect(model.hiding == .closed)
    #expect(phone.saved.count == 1)
  }

  @Test func aHuntMakesTheCatGiveWarmthAndFindingPaysViaTheJournal() {
    let phone = Phone()
    let model = Self.model(phone)
    Self.partnerHid(model)
    #expect(model.theirs?.spot == .basket)
    model.beginHunt()
    #expect(model.isHunting)
    model.look(at: .crate)
    model.look(at: .sofa)
    phone.now = Self.t0.addingTimeInterval(30)
    model.look(at: .basket)
    #expect(phone.hints == [.away, .sniffs(at: .basket), .pounces(on: .basket)])
    #expect(
      phone.recorded == [
        .mouseFound(hidden: IdempotencyKey("h1"), spot: "basket", tries: 3, seconds: 30)
      ])
    #expect(phone.played == [.found])
    #expect(model.theirs == nil)
    #expect(model.over.first?.hide.id == "h1")
  }

  @Test func theCatIsPlainAfterThreeMisses() {
    let phone = Phone()
    let model = Self.model(phone)
    Self.partnerHid(model)
    model.beginHunt()
    for spot in [MischiefSpot.crate, .tree, .sill] { model.look(at: spot) }
    #expect(phone.hints.last == .leads(to: .basket))
  }

  @Test func nothingToHuntWhenNothingIsHidden() {
    let model = Self.model(Phone())
    model.beginHunt()
    #expect(!model.isHunting)
  }

  @Test func theHidersOwnMouseIsNotTheirToHunt() {
    let phone = Phone()
    let model = Self.model(phone, me: "leo", partner: "mia")
    Self.partnerHid(model)
    #expect(model.theirs == nil)
    #expect(model.mine?.spot == .basket)
  }

  @Test func theMouseGoingStopsAHuntInProgress() {
    let phone = Phone()
    let model = Self.model(phone)
    Self.partnerHid(model)
    model.beginHunt()
    phone.now = Self.t0.addingTimeInterval(4 * 86_400)
    model.receive(
      CatEntry(
        seq: 3, id: IdempotencyKey("h2"), by: UserId("leo"), at: MischiefLedgerTests.ms(phone.now),
        event: .mouseHidden(spot: "tree", line: nil)))
    #expect(!model.isHunting)
    #expect(model.theirs?.id == "h2")
  }

  @Test func theMouseWaitsAcrossALongAbsence() {
    let phone = Phone()
    let model = Self.model(phone)
    Self.partnerHid(model)
    phone.now = Self.t0.addingTimeInterval(2 * 86_400)
    #expect(model.theirs != nil)
  }

  @Test func aSpotThatWentAwayIsStillOnTheHuntersList() {
    let model = Self.model(Phone())
    #expect(!model.spots().contains(.bowl))
    #expect(model.spots(including: .bowl).contains(.bowl))
  }

  @Test func forgettingClearsAllOfIt() {
    let phone = Phone()
    let model = Self.model(phone)
    Self.partnerHid(model)
    model.beginHunt()
    model.forget()
    #expect(model.theirs == nil && !model.isHunting)
  }

  @Test func withoutAPairNothingIsSent() {
    let phone = Phone()
    let model = Self.model(phone, paired: false)
    model.send(.opened)
    model.send(.picked(.sofa))
    model.send(.submitted)
    #expect(phone.recorded.isEmpty)
  }
}
