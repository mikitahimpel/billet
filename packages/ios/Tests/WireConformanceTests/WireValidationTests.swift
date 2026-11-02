import Foundation
import Testing

@testable import Wire

/// What Wire refuses to decode. The schema in packages/contracts says each of these is invalid, so
/// a server that sent one has broken the contract and the client says so instead of passing it on.
@Suite struct WireValidationTests {
  private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
  }

  private func expectRejected<T: Decodable>(_ type: T.Type, _ json: String) {
    #expect(throws: DecodingError.self) { try decode(type, json) }
  }

  // MARK: colour

  @Test(arguments: ["#2A1A1C", "#2a1a1c", "#000000", "#fFfFfF"])
  func strokesAcceptRRGGBBInEitherCase(_ color: String) throws {
    let stroke = try decode(Stroke.self, ##"{"color":"\##(color)","width":0.01,"points":[]}"##)
    #expect(stroke.color == color)
  }

  @Test(arguments: [
    "red", "#000", "#00000", "#0000000", "000000", "#GGGGGG", "#+00000", "# 00000", "",
  ])
  func strokesRejectAnythingElse(_ color: String) {
    expectRejected(Stroke.self, ##"{"color":"\##(color)","width":0.01,"points":[]}"##)
  }

  @Test(arguments: ["red", "#000", "000000", "#GGGGGG", ""])
  func compactStrokesRejectAnythingElse(_ color: String) {
    expectRejected(CompactStroke.self, ##"{"color":"\##(color)","width":1,"points":[1,2]}"##)
  }

  @Test func compactStrokesAcceptAValidColour() throws {
    let stroke = try decode(CompactStroke.self, ##"{"color":"#A1B2C3","width":1,"points":[1,2]}"##)
    #expect(stroke.points == [1, 2])
  }

  // MARK: points

  @Test(arguments: ["[1]", "[1,2,3]", "[1,2,3,4,5]"])
  func compactPointsMustComeInPairs(_ points: String) {
    expectRejected(CompactStroke.self, ##"{"color":"#000000","width":1,"points":\##(points)}"##)
  }

  @Test(arguments: ["[]", "[1,2]", "[1,2,3,4]"])
  func compactPointsAcceptWholePairs(_ points: String) throws {
    let stroke = try decode(
      CompactStroke.self, ##"{"color":"#000000","width":1,"points":\##(points)}"##)
    #expect(stroke.points.count.isMultiple(of: 2))
  }

  @Test func anInvalidStrokeInsideCompactStrokesRejectsTheWhole() {
    expectRejected(
      CompactStrokes.self,
      ##"{"version":1,"strokes":[{"color":"#000000","width":1,"points":[1]}]}"##)
  }

  // MARK: sentAt

  private func note(sentAt: String) -> String {
    ##"{"_tag":"Photo","id":"n1","author":"u1","sentAt":\##(sentAt),"image":"k1"}"##
  }

  private func drawing(sentAt: String) -> String {
    ##"{"_tag":"Drawing","id":"n1","author":"u1","sentAt":\##(sentAt),"compact":{"version":1,"strokes":[]},"image":"k1"}"##
  }

  @Test func aNegativeSentAtIsRejected() {
    expectRejected(Note.self, note(sentAt: "-1"))
    expectRejected(Note.self, drawing(sentAt: "-1"))
  }

  @Test func sentAtOfZeroOrMoreIsAccepted() throws {
    _ = try decode(Note.self, note(sentAt: "0"))
    _ = try decode(Note.self, drawing(sentAt: "1767225600000"))
  }

  // MARK: idempotency key and invite expiry

  @Test(arguments: ["", "not-a-uuid", "6f1c2d3e4a5b4c6d8e7f0a1b2c3d4e5f"])
  func aKeyThatIsNotAUUIDIsRejected(_ key: String) {
    expectRejected(SendNoteRequest.self, ##"{"_tag":"Photo","key":"\##(key)","image":"k1"}"##)
  }

  @Test func aNoteRequestNeedsItsKey() {
    expectRejected(SendNoteRequest.self, ##"{"_tag":"Photo","image":"k1"}"##)
  }

  @Test func aUUIDKeyIsAcceptedInEitherCase() throws {
    _ = try decode(
      SendNoteRequest.self,
      ##"{"_tag":"Photo","key":"6F1C2D3E-4A5B-4C6D-8E7F-0A1B2C3D4E5F","image":"k1"}"##)
    _ = try decode(
      SendNoteRequest.self,
      ##"{"_tag":"Photo","key":"6f1c2d3e-4a5b-4c6d-8e7f-0a1b2c3d4e5f","image":"k1"}"##)
  }

  @Test func aNegativeInviteExpiryIsRejected() {
    expectRejected(CreateInviteResponse.self, ##"{"code":"ABCD2345EF","expiresAt":-1}"##)
  }

  // MARK: flags

  @Test(arguments: [
    ##"{"flags":[{"key":"","variant":"a"}]}"##,
    ##"{"flags":[{"key":"a","variant":""}]}"##,
    ##"{"flags":[{"key":"a"}]}"##,
  ])
  func aFlagNeedsAKeyAndAVariant(_ json: String) {
    expectRejected(FlagsResponse.self, json)
  }

  @Test func anEmptyFlagListIsAccepted() throws {
    #expect(try decode(FlagsResponse.self, ##"{"flags":[]}"##).flags.isEmpty)
  }

  // MARK: push payload

  @Test func aNullCompactIsRejected() {
    expectRejected(
      PushPayload.self, ##"{"_tag":"Widget","noteId":"n1","author":"u1","compact":null}"##)
  }

  @Test func anAbsentCompactIsAccepted() throws {
    let payload = try decode(PushPayload.self, ##"{"_tag":"Alert","noteId":"n1","author":"u1"}"##)
    #expect(payload == .alert(noteId: NoteId("n1"), author: UserId("u1"), compact: nil))
  }

  @Test func aPresentCompactIsAccepted() throws {
    let payload = try decode(
      PushPayload.self,
      ##"{"_tag":"Widget","noteId":"n1","author":"u1","compact":{"version":1,"strokes":[]}}"##)
    #expect(
      payload
        == .widget(
          noteId: NoteId("n1"), author: UserId("u1"), compact: CompactStrokes(strokes: [])))
  }
}
