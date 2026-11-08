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

  /// A photo send with the size and preview it must carry, so these cases test only the key.
  private func photoSend(key: String?) -> String {
    let keyField = key.map { #","key":"\#($0)""# } ?? ""
    return #"{"_tag":"Photo","image":"k1""# + keyField
      + #","width":3,"height":4,"preview":"LEHV6nWB2yk8pyo0adR*.7kCMdnj"}"#
  }

  @Test(arguments: ["", "not-a-uuid", "6f1c2d3e4a5b4c6d8e7f0a1b2c3d4e5f"])
  func aKeyThatIsNotAUUIDIsRejected(_ key: String) {
    expectRejected(SendNoteRequest.self, photoSend(key: key))
  }

  @Test func aNoteRequestNeedsItsKey() {
    expectRejected(SendNoteRequest.self, photoSend(key: nil))
  }

  @Test func aUUIDKeyIsAcceptedInEitherCase() throws {
    _ = try decode(SendNoteRequest.self, photoSend(key: "6F1C2D3E-4A5B-4C6D-8E7F-0A1B2C3D4E5F"))
    _ = try decode(SendNoteRequest.self, photoSend(key: "6f1c2d3e-4a5b-4c6d-8e7f-0a1b2c3d4e5f"))
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

  // MARK: reported events

  @Test(arguments: ["NoteSent", "PairClaimed", "InviteCreated", "Anything", ""])
  func anEventTheServerRecordsItselfOrDoesNotKnowIsRejected(_ name: String) {
    expectRejected(ReportEventsRequest.self, ##"{"events":["\##(name)"]}"##)
  }

  @Test func moreEventsThanOneRequestHoldsAreRejected() throws {
    let many = Array(repeating: ##""AppOpened""##, count: ReportEventsRequest.maxEvents + 1)
    expectRejected(ReportEventsRequest.self, ##"{"events":[\##(many.joined(separator: ","))]}"##)
    let enough = Array(repeating: ##""AppOpened""##, count: ReportEventsRequest.maxEvents)
    _ = try decode(ReportEventsRequest.self, ##"{"events":[\##(enough.joined(separator: ","))]}"##)
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

  // MARK: text notes and paper

  private func textNote(_ text: String, paper: String? = nil) -> String {
    let paperField = paper.map { ##","paper":\##($0)"## } ?? ""
    let fields = ##""id":"n1","author":"u1","sentAt":0"##
    return ##"{"_tag":"Text",\##(fields),"text":"\##(text)"\##(paperField)}"##
  }

  @Test func aTextNoteDecodesWithAndWithoutPaper() throws {
    #expect(
      try decode(Note.self, textNote("hi", paper: ##""sage""##))
        == .text(
          id: NoteId("n1"), author: UserId("u1"), sentAt: 0, text: NoteText(validating: "hi")!,
          paper: .sage))
    #expect(
      try decode(Note.self, textNote("hi"))
        == .text(
          id: NoteId("n1"), author: UserId("u1"), sentAt: 0, text: NoteText(validating: "hi")!))
  }

  @Test(arguments: [##""mint""##, "null", ##""""##])
  func anUnknownOrNullPaperIsRejected(_ paper: String) {
    expectRejected(Note.self, textNote("hi", paper: paper))
  }

  @Test(arguments: ["", "   ", String(repeating: "a", count: NoteText.maxCharacters + 1)])
  func aBlankOrLongTextIsRejected(_ text: String) {
    expectRejected(Note.self, textNote(text))
    #expect(NoteText(validating: text) == nil)
  }

  /// JavaScript's `trim()`, which the server uses, and Swift's `isWhitespace` disagree on these.
  @Test func blankMeansWhatTheServerTrims() throws {
    #expect(NoteText(validating: "\u{FEFF}") == nil)
    #expect(NoteText(validating: "\u{3000}\u{2009}") == nil)
    #expect(NoteText(validating: "\u{85}") != nil)
    _ = try decode(Note.self, textNote(#"\u0085"#))
  }

  // MARK: stamps and seals

  private func decorated(_ decoration: String) -> String {
    ##"{"_tag":"Text","id":"n1","author":"u1","sentAt":0,"text":"hi",\##(decoration)}"##
  }

  @Test func aTextNoteKeepsItsStampAndSeal() throws {
    let note = try decode(Note.self, decorated(##""stamp":"moon","seal":"rose""##))
    #expect(
      note
        == .text(
          id: NoteId("n1"), author: UserId("u1"), sentAt: 0, text: NoteText(validating: "hi")!,
          stamp: .moon, seal: .rose))
  }

  /// A newer app may add designs; the note still arrives, plain.
  @Test func aStampOrSealThisBuildDoesNotKnowReadsAsNone() throws {
    let note = try decode(Note.self, decorated(##""stamp":"dragon","seal":"glitter""##))
    #expect(
      note
        == .text(
          id: NoteId("n1"), author: UserId("u1"), sentAt: 0, text: NoteText(validating: "hi")!))
  }

  @Test(arguments: [##""stamp":null"##, ##""seal":null"##, ##""stamp":3"##])
  func aNullOrNonStringStampOrSealIsRejected(_ decoration: String) {
    expectRejected(Note.self, decorated(decoration))
  }

  @Test func aSentTextNoteCarriesItsStampAndSeal() throws {
    let request = SendNoteRequest.text(
      key: IdempotencyKey("k"), text: NoteText(validating: "hi")!, stamp: .paw, seal: .night)
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request))
    let fields = try #require(object as? [String: Any])
    #expect(fields["stamp"] as? String == "paw")
    #expect(fields["seal"] as? String == "night")
  }

  // MARK: pages skip what this build can't read

  @Test func aNotesPageSkipsAnUnknownKindButCountsItsSeq() throws {
    let known = #"{"seq":1,"note":\#(textNote("hi"))}"#
    let unknown = #"{"seq":2,"note":{"_tag":"Hologram","id":"n2","author":"u1","sentAt":0}}"#
    let page = try decode(ListNotesResponse.self, #"{"notes":[\#(known),\#(unknown)]}"#)
    #expect(page.notes.map(\.seq) == [1])
    #expect(page.lastSeq == 2)
    #expect(try decode(ListNotesResponse.self, #"{"notes":[]}"#).lastSeq == nil)
  }

  @Test func anActivityPageSkipsAnItemItCantRead() throws {
    let item = ActivityItem(
      id: "a1", at: 0, actor: .partner, event: .catPetted, target: .cat, cursor: "c1")
    let good = String(decoding: try JSONEncoder().encode(item), as: UTF8.self)
    let bad = good.replacingOccurrences(of: #""_tag":"Cat""#, with: #""_tag":"Hologram""#)
    #expect(bad != good)
    let page = try decode(ActivityResponse.self, #"{"items":[\#(good),\#(bad)],"unread":0}"#)
    #expect(page.items == [item])
  }

  @Test func aShopCatalogSkipsAnItemItCantRead() throws {
    let good = ShopCatalogItem(
      id: "lamp", kind: "decor", name: "Lamp", rarity: .rare, price: 140, section: "decor",
      sortOrder: 10, asset: .bundled(id: "lamp"))
    let json = String(decoding: try JSONEncoder().encode(good), as: UTF8.self)
    let bad = json.replacingOccurrences(of: #""rarity":"rare""#, with: #""rarity":"mythic""#)
    #expect(bad != json)
    let catalog = try decode(
      ShopCatalogResponse.self, #"{"version":"0123456789abcdef","items":[\#(bad),\#(json)]}"#)
    #expect(catalog.items == [good])
  }

  @Test func aSaleHoldsOnlyInsideItsWindow() {
    let item = ShopCatalogItem(
      id: "lamp", kind: "decor", name: "Lamp", rarity: .rare, price: 140,
      sale: ShopSale(price: 100, from: 1_000, until: 2_000), section: "decor", sortOrder: 10,
      asset: .bundled(id: "lamp"))
    #expect(item.effectivePrice(at: Date(timeIntervalSince1970: 0.9)) == 140)
    #expect(item.effectivePrice(at: Date(timeIntervalSince1970: 1.0)) == 100)
    #expect(item.effectivePrice(at: Date(timeIntervalSince1970: 2.0)) == 140)
  }

  @Test func textCountsCharactersAsAPersonDoes() throws {
    let family = String(repeating: "👩‍👩‍👧‍👦", count: NoteText.maxCharacters)
    #expect(NoteText(validating: family) != nil)
    _ = try decode(Note.self, textNote(family))
    #expect(NoteText(validating: String(repeating: "💛", count: NoteText.maxCharacters + 1)) == nil)
  }

  @Test func aDrawingKeepsItsPaper() throws {
    let note = try decode(
      Note.self,
      ##"{"_tag":"Drawing","id":"n1","author":"u1","sentAt":0,"compact":{"version":1,"strokes":[]},"image":"k1","paper":"blush"}"##
    )
    guard case .drawing(_, _, _, _, _, let paper, _, _) = note else {
      Issue.record("expected a drawing")
      return
    }
    #expect(paper == .blush)
  }

  @Test func aTextPushCarriesItsWords() throws {
    let payload = try decode(
      PushPayload.self,
      ##"{"_tag":"Widget","noteId":"n1","author":"u1","text":"hi","paper":"sky"}"##)
    #expect(
      payload
        == .widget(
          noteId: NoteId("n1"), author: UserId("u1"), compact: nil,
          text: NoteText(validating: "hi"), paper: .sky))
    expectRejected(
      PushPayload.self, ##"{"_tag":"Alert","noteId":"n1","author":"u1","text":null}"##)
  }

  // MARK: onboarding

  private let title = ##"{"en":"t","ru":"т"}"##

  @Test func aChoiceStepKeepsItsOptionsAndFlags() throws {
    let step = try decode(
      OnboardingStep.self,
      ##"{"_tag":"Multi","id":"goals","title":\##(title),"skippable":true,"options":[{"id":"a","label":\##(title),"exclusive":true}]}"##
    )
    guard case .multi(let multi) = step else {
      Issue.record("expected a multi step")
      return
    }
    #expect(step.id == "goals")
    #expect(multi.options.first?.exclusive == true)
    #expect(multi.options.first?.emoji == nil)
  }

  @Test(arguments: [
    ##"{"_tag":"Single","id":"s","title":{"en":"t","ru":"т"},"skippable":true,"options":[]}"##,
    ##"{"_tag":"Single","id":"s","title":{"en":"t","ru":"т"},"skippable":true,"subtitle":null,"options":[{"id":"a","label":{"en":"t","ru":"т"}}]}"##,
    ##"{"_tag":"Range","id":"r","title":{"en":"t","ru":"т"},"skippable":true,"min":0,"max":9,"step":0}"##,
    ##"{"_tag":"Text","id":"t","title":{"en":"t","ru":"т"},"skippable":true,"maxLength":0}"##,
    ##"{"_tag":"Date","id":"d","title":{"en":"t","ru":"т"},"skippable":true}"##,
  ])
  func aBrokenStepIsRejected(_ json: String) {
    expectRejected(OnboardingStep.self, json)
  }

  @Test(arguments: [
    ##"{"_tag":"Multi","options":[]}"##,
    ##"{"_tag":"Multi","options":["a","a"]}"##,
    ##"{"_tag":"Text","text":"  "}"##,
    ##"{"_tag":"Single"}"##,
  ])
  func aBrokenAnswerIsRejected(_ json: String) {
    expectRejected(OnboardingAnswer.self, json)
  }

  @Test func anAnswerRequestEncodesAsTheServerReadsIt() throws {
    let request = SaveOnboardingAnswerRequest(
      version: "2026-11-04", stepId: "cat_coat", answer: .single(option: "grey"),
      answeredAt: 1000)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    #expect(
      String(decoding: try encoder.encode(request), as: UTF8.self)
        == ##"{"answer":{"_tag":"Single","option":"grey"},"answeredAt":1000,"stepId":"cat_coat","version":"2026-11-04"}"##
    )
  }
}
