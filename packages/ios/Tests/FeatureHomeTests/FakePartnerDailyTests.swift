import FeatureInbox
import Foundation
import Pet
import Testing
import Wire

@testable import FeatureHome

@Suite("FakePartnerDaily")
struct FakePartnerDailyTests {
  private static let pace = FakePartnerPace(
    arrival: .milliseconds(1), open: .seconds(60), reaction: .seconds(60), reply: .seconds(60),
    petBack: .seconds(60), treatBack: .seconds(60), sealedFor: .seconds(60),
    holdFor: .seconds(60), adventDoors: [], giftOpened: .seconds(60), lampFollows: .seconds(60),
    idle: [], dailyDraws: .milliseconds(20))

  private let drawing = [Stroke(color: "#000000", width: 0.02, points: [Point(x: 0.5, y: 0.5)])]

  /// Reads updates until `stop` holds for one, acting once the partner has said it is here.
  private func dailies(
    _ delivery: NoteDelivery, act: @Sendable () async -> Void = {},
    until stop: (DailyEntry) -> Bool
  ) async -> [DailyEntry] {
    var seen: [DailyEntry] = []
    var acted = false
    for await update in delivery.updates() {
      switch update {
      case .status(.partnerHere) where !acted:
        acted = true
        await act()
      case .daily(let entry):
        seen.append(entry)
        if stop(entry) { return seen }
      default:
        break
      }
    }
    return seen
  }

  @Test func thePartnersDrawingStaysHiddenUntilTheUserDraws() async {
    let delivery = NoteDelivery.fakePartner(device: "me", room: FakePartnerRoom(pace: Self.pace))
    let before = await dailies(delivery) { $0.theirsDrawn }
    #expect(before.last?.theirsDrawn == true)
    #expect(before.last?.theirs == nil)
  }

  @Test func drawingRevealsBoth() async {
    let delivery = NoteDelivery.fakePartner(device: "me", room: FakePartnerRoom(pace: Self.pace))
    let today = TreatDay.timestamp(for: .now, calendar: .current)
    let drawing = drawing
    let seen = await dailies(
      delivery, act: { await delivery.drawDaily(drawing, today) }, until: { $0.theirs != nil })
    #expect(seen.last?.mine == drawing)
    #expect(seen.last?.theirs != nil)
  }
}
