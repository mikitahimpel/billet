import Foundation
import Testing

@testable import Wire

/// Decodes a fixture into its Wire type and encodes it back to JSON.
typealias RoundTrip = @Sendable (Data) throws -> Data

/// Decodes with `T`, then encodes the result back.
func codec<T: Codable & Sendable>(_ type: T.Type) -> RoundTrip {
  { data in
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(JSONDecoder().decode(T.self, from: data))
  }
}

/// Maps a fixture's top-level directory name to the Wire type that must round-trip it.
/// Every Wire type adds its entry here; a fixture without one fails.
let roundTrips: [String: RoundTrip] = [
  "PairId": codec(PairId.self),
  "CompactStrokes": codec(CompactStrokes.self),
  "Stroke": codec(Stroke.self),
  "Note": codec(Note.self),
  "DeliveryLane": codec(DeliveryLane.self),
  "CreateInviteResponse": codec(CreateInviteResponse.self),
  "ClaimInviteRequest": codec(ClaimInviteRequest.self),
  "ClaimInviteResponse": codec(ClaimInviteResponse.self),
  "UploadImageResponse": codec(UploadImageResponse.self),
  "SendNoteRequest": codec(SendNoteRequest.self),
  "SendNoteResponse": codec(SendNoteResponse.self),
  "ListNotesResponse": codec(ListNotesResponse.self),
  "FlagsResponse": codec(FlagsResponse.self),
  "StatusResponse": codec(StatusResponse.self),
  "MaintenanceResponse": codec(MaintenanceResponse.self),
  "ReportEventsRequest": codec(ReportEventsRequest.self),
  "AuthChallengeResponse": codec(AuthChallengeResponse.self),
  "SignInWithAppleRequest": codec(SignInWithAppleRequest.self),
  "SignInAnonymouslyRequest": codec(SignInAnonymouslyRequest.self),
  "AccountResponse": codec(AccountResponse.self),
  "DeleteAccountRequest": codec(DeleteAccountRequest.self),
  "SessionResponse": codec(SessionResponse.self),
  "RegisterPushTokenRequest": codec(RegisterPushTokenRequest.self),
  "ApiError": codec(ApiError.self),
  "Ink": codec(Ink.self),
  "InksResponse": codec(InksResponse.self),
  "CoinEntry": codec(CoinEntry.self),
  "CoinsResponse": codec(CoinsResponse.self),
  "BuyRequest": codec(BuyRequest.self),
  "BuyResponse": codec(BuyResponse.self),
  "ShopOffer": codec(ShopOffer.self),
  "ShopResponse": codec(ShopResponse.self),
  "OrderRequest": codec(OrderRequest.self),
  "OrderResponse": codec(OrderResponse.self),
  "WishRequest": codec(WishRequest.self),
  "PairResponse": codec(PairResponse.self),
  "ClientMessage": codec(ClientMessage.self),
  "ServerMessage": codec(ServerMessage.self),
  "PushPayload": codec(PushPayload.self),
  "PurchaseRequest": codec(PurchaseRequest.self),
  "MockPurchaseRequest": codec(MockPurchaseRequest.self),
  "PurchaseResponse": codec(PurchaseResponse.self),
  "PurchasesResponse": codec(StampsResponse.self),
  "AppStoreNotificationRequest": codec(AppStoreNotificationRequest.self),
  "OnboardingStep": codec(OnboardingStep.self),
  "OnboardingAnswer": codec(OnboardingAnswer.self),
  "OnboardingResponse": codec(OnboardingResponse.self),
  "SaveOnboardingAnswerRequest": codec(SaveOnboardingAnswerRequest.self),
  "CatEvent": codec(CatEvent.self),
  "CatEntry": codec(CatEntry.self),
  "CatProfile": codec(CatProfile.self),
  "CatTemper": codec(CatTemper.self),
  "CatNeeds": codec(CatNeeds.self),
  "CatResponse": codec(CatResponse.self),
  "SaveCatRequest": codec(SaveCatRequest.self),
  "RecordCatEventRequest": codec(RecordCatEventRequest.self),
  "RecordCatEventResponse": codec(RecordCatEventResponse.self),
  "CatJournalResponse": codec(CatJournalResponse.self),
  "ActivityEvent": codec(ActivityEvent.self),
  "ActivityTarget": codec(ActivityTarget.self),
  "ActivityItem": codec(ActivityItem.self),
  "ActivityResponse": codec(ActivityResponse.self),
  "MarkActivityReadRequest": codec(MarkActivityReadRequest.self),
  "ActivityUnreadResponse": codec(ActivityUnreadResponse.self),
  "NoteReaction": codec(NoteReaction.self),
  "ReactRequest": codec(ReactRequest.self),
  "ReactResponse": codec(ReactResponse.self),
  "ListReactionsResponse": codec(ListReactionsResponse.self),
  "GiftWish": codec(GiftWish.self),
  "GiftsResponse": codec(GiftsResponse.self),
  "SaveGiftWishRequest": codec(SaveGiftWishRequest.self),
  "DeleteGiftWishRequest": codec(DeleteGiftWishRequest.self),
  "SetGiftPlanRequest": codec(SetGiftPlanRequest.self),
  "MarkGiftReceivedRequest": codec(MarkGiftReceivedRequest.self),
  "SaveLovesRequest": codec(SaveLovesRequest.self),
]

let fixturesDirectory = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent()
  .appending(path: "packages/contracts/fixtures/golden", directoryHint: .isDirectory)

func fixtureURLs() -> [URL] {
  guard
    let files = FileManager.default.enumerator(
      at: fixturesDirectory, includingPropertiesForKeys: nil)
  else { return [] }
  return files.compactMap { $0 as? URL }
    .filter { $0.pathExtension == "json" }
    .sorted { $0.path < $1.path }
}

struct Mismatch: Error, CustomStringConvertible {
  let description: String
}

func roundTrip(fixture url: URL) throws {
  let relative = url.path.dropFirst(fixturesDirectory.path.count + 1)
  guard let family = relative.split(separator: "/").first.map(String.init),
    relative.contains("/")
  else {
    throw Mismatch(description: "\(relative): fixtures live in <Type>/<case>.json")
  }
  guard let transform = roundTrips[family] else {
    throw Mismatch(description: "\(relative): no Wire round trip registered for \(family)")
  }
  let original = try Data(contentsOf: url)
  let encoded = try transform(original)
  guard compact(original) == compact(encoded) else {
    throw Mismatch(description: "\(relative): re-encoded JSON differs from the fixture")
  }
}

/// Strips whitespace outside strings and keeps every other byte, so `1`, `1.0`, `true` and key
/// order must match the fixture exactly. Fixtures are canonical (sorted keys), so a round trip
/// must encode with `.sortedKeys` and `.withoutEscapingSlashes`.
func compact(_ data: Data) -> [UInt8] {
  var output: [UInt8] = []
  var inString = false
  var escaped = false
  for byte in data {
    if inString {
      if escaped {
        escaped = false
      } else if byte == UInt8(ascii: "\\") {
        escaped = true
      } else if byte == UInt8(ascii: "\"") {
        inString = false
      }
      output.append(byte)
    } else if byte == UInt8(ascii: "\"") {
      inString = true
      output.append(byte)
    } else if ![0x20, 0x09, 0x0A, 0x0D].contains(byte) {
      output.append(byte)
    }
  }
  return output
}

@Test("Wire round-trips fixture", arguments: fixtureURLs())
func wireRoundTrips(fixture: URL) throws {
  try roundTrip(fixture: fixture)
}

@Test("Golden fixtures exist")
func goldenFixturesExist() {
  #expect(
    !fixtureURLs().isEmpty,
    "No fixtures found in \(fixturesDirectory.path); conformance would check nothing.")
}
