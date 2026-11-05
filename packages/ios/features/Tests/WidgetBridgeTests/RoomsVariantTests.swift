import Testing

@testable import WidgetBridge

/// The phone's side of the `rooms` experiment: what each variant shows, and what wins.
@Suite struct RoomsVariantTests {
  @Test(arguments: RoomsVariant.allCases)
  func everyVariantIsTheServersAndBack(_ variant: RoomsVariant) {
    #expect(Experiments.rooms.variants.contains(variant.remoteVariant))
    #expect(RoomsVariant(remoteVariant: variant.remoteVariant) == variant)
  }

  @Test func theVariantIdsAreKebabCase() {
    #expect(RoomsVariant.allCases.map(\.remoteVariant) == ["both", "room-only", "city-only"])
  }

  @Test func eachVariantHasItsRooms() {
    #expect(RoomsVariant.both.rooms == [.room, .city])
    #expect(RoomsVariant.roomOnly.rooms == [.room])
    #expect(RoomsVariant.cityOnly.rooms == [.city])
  }

  @Test func onlyBothHasTheSwitch() {
    #expect(RoomsVariant.both.hasRoomChoice)
    #expect(!RoomsVariant.roomOnly.hasRoomChoice)
    #expect(!RoomsVariant.cityOnly.hasRoomChoice)
  }

  @Test func oneRoomOpensOnThatRoom() {
    #expect(RoomsVariant.both.firstRoom == .room)
    #expect(RoomsVariant.roomOnly.firstRoom == .room)
    #expect(RoomsVariant.cityOnly.firstRoom == .city)
  }

  @Test func nothingFromTheServerMeansBoth() {
    #expect(RoomsVariant.resolved(labs: nil, remote: RemoteFlags()) == .both)
  }

  @Test func anUnknownVariantMeansBoth() {
    let remote = RemoteFlags(assignments: ["rooms": "attic-only"])
    #expect(RoomsVariant.resolved(labs: nil, remote: remote) == .both)
  }

  @Test func thePairsVariantIsShown() {
    let remote = RemoteFlags(assignments: ["rooms": "city-only"])
    #expect(RoomsVariant.resolved(labs: nil, remote: remote) == .cityOnly)
  }

  @Test func aLabsChoiceBeatsThePairsVariant() {
    let remote = RemoteFlags(assignments: ["rooms": "city-only"])
    #expect(RoomsVariant.resolved(labs: .roomOnly, remote: remote) == .roomOnly)
  }
}
