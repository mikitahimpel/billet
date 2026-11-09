import Foundation
import Testing

@testable import Wire

@Suite struct ClientEventWireTests {
  private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
  }

  private func expectRejected<T: Decodable>(_ type: T.Type, _ json: String) {
    #expect(throws: DecodingError.self) { try decode(type, json) }
  }

  // MARK: both forms

  @Test func theDetailedGoldenHoldsBothForms() throws {
    let url = fixturesDirectory.appending(path: "ReportEventsRequest/detailed.json")
    let request = try JSONDecoder().decode(ReportEventsRequest.self, from: Data(contentsOf: url))
    #expect(
      request.clientEvents == [
        ClientEvent(.appOpened), ClientEvent(.catChosen, detail: "marmalade"),
        ClientEvent(.noteOpened, detail: "widget"),
        ClientEvent(.shopItemBought, detail: "fairy-lights", value: 40), ClientEvent(.catPetted),
      ])
    #expect(request.events.first == .event(ClientEvent(.appOpened)))
    #expect(request.events.last == .name(.catPetted))
  }

  @Test func aBareNameMeansTheSameAsAnObjectWithoutADetail() throws {
    let bare = try decode(ReportEventsRequest.self, #"{"events":["AppOpened"]}"#)
    let object = try decode(ReportEventsRequest.self, #"{"events":[{"name":"AppOpened"}]}"#)
    #expect(bare.clientEvents == object.clientEvents)
  }

  @Test func thisBuildSendsObjects() throws {
    let request = ReportEventsRequest(events: [
      ClientEvent(.appOpened), ClientEvent(.catFed, detail: "treat"),
    ])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    #expect(
      String(decoding: try encoder.encode(request), as: UTF8.self)
        == #"{"events":[{"name":"AppOpened"},{"detail":"treat","name":"CatFed"}]}"#)
  }

  @Test func theAnalyticsSwitchDecodesAndIsOnWhenAbsent() throws {
    let url = fixturesDirectory.appending(path: "StatusResponse/analytics-off.json")
    let status = try JSONDecoder().decode(StatusResponse.self, from: Data(contentsOf: url)).status
    #expect(status.analytics == AnalyticsStatus(enabled: false))
    #expect(!status.analyticsEnabled)
    #expect(AppStatus.normal.analyticsEnabled)
    let on = try decode(
      AppStatus.self, #"{"maintenance":{"active":false},"analytics":{"enabled":true}}"#)
    #expect(on.analyticsEnabled)
  }

  // MARK: rules

  @Test(arguments: [
    #"{"name":"AppOpened","detail":"x"}"#,
    #"{"name":"CatFed"}"#,
    #"{"name":"CatFed","detail":"cake"}"#,
    #"{"name":"TrickDone"}"#,
    #"{"name":"NoteOpened","detail":"push"}"#,
    #"{"name":"CatChosen","detail":"9lives"}"#,
    #"{"name":"CatChosen","detail":"grey_tabby"}"#,
    #"{"name":"CatChosen","detail":"a.b"}"#,
    #"{"name":"CatChosen","detail":""}"#,
    #"{"name":"CatChosen","detail":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#,
    #"{"name":"ShopItemViewed","detail":"fish","value":3}"#,
    #"{"name":"ShopItemBought","detail":"fish","value":-1}"#,
    #"{"name":"ShopItemBought","detail":"fish","value":100001}"#,
    #"{"name":"ShopItemBought","detail":"fish","value":1.5}"#,
    #"{"name":"NoteSent"}"#,
  ])
  func anEventThatBreaksItsRuleIsRejected(_ event: String) {
    expectRejected(ReportEventsRequest.self, #"{"events":[\#(event)]}"#)
  }

  @Test(arguments: [
    #"{"name":"WidgetAdded"}"#,
    #"{"name":"WidgetAdded","detail":"LatestNote"}"#,
    #"{"name":"CatPlayed"}"#,
    #"{"name":"CatChosen","detail":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#,
    #"{"name":"ShopItemBought","detail":"fish","value":0}"#,
    #"{"name":"ShopItemBought","detail":"fish","value":100000}"#,
    #"{"name":"SignInPromptAnswered","detail":"accepted"}"#,
  ])
  func anEventThatKeepsItsRuleIsAccepted(_ event: String) throws {
    _ = try decode(ReportEventsRequest.self, #"{"events":[\#(event)]}"#)
  }

  @Test(
    arguments: [
      ("Pet_Pose.v2", "Pet-Pose-v2"), ("LatestNote", "LatestNote"), ("2up", nil),
      ("", nil), (String(repeating: "a", count: 50), String(repeating: "a", count: 40)),
    ] as [(String, String?)])
  func aRawIDIsMadeADetailTheSameWayEachTime(_ raw: String, _ detail: String?) {
    #expect(ClientEvent.detail(from: raw) == detail)
  }

  // MARK: the contract

  static func contract() throws -> (names: [String], rules: [String: ClientEventRule]) {
    let file = fixturesDirectory.deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "domain/src/metrics.ts")
    let source = try String(contentsOf: file, encoding: .utf8)

    let namesStart = try #require(source.firstRange(of: "export const ClientEventName")).upperBound
    let namesEnd = try #require(source[namesStart...].firstRange(of: "]);")).lowerBound
    let names = source[namesStart..<namesEnd]
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.hasPrefix("/") && !$0.hasPrefix("*") }
      .compactMap { $0.firstMatch(of: #/^"([A-Za-z]+)",?$/#).map { String($0.1) } }

    let rulesStart = try #require(source.firstRange(of: "export const clientEventRules"))
      .upperBound
    let rulesBody = try #require(source[rulesStart...].firstRange(of: "\n};")).lowerBound
    var rules: [String: ClientEventRule] = [:]
    let entry = #/^\s*([A-Za-z]+):\s*\{(.*)\},?\s*$/#
    for line in source[rulesStart..<rulesBody].split(separator: "\n") {
      guard let match = line.firstMatch(of: entry) else { continue }
      let body = match.2
      let detail: ClientEventRule.Detail
      if body.contains(#"detail: "none""#) {
        detail = .none
      } else if body.contains(#"detail: "id""#) {
        detail = .id
      } else {
        let list = try #require(body.firstMatch(of: #/detail:\s*\[([^\]]*)\]/#)).1
        detail = .oneOf(list.matches(of: #/"([^"]+)"/#).map { String($0.1) })
      }
      rules[String(match.1)] = ClientEventRule(
        detail: detail, required: body.contains("required: true"),
        value: body.contains("value: true"))
    }
    return (names, rules)
  }

  @Test func theNamesAreTheContracts() throws {
    let names = try Self.contract().names
    #expect(names.count >= 26)
    #expect(names == ClientEventName.allCases.map(\.rawValue))
  }

  @Test func theContractHasARuleForEveryName() throws {
    #expect(Set(try Self.contract().rules.keys) == Set(ClientEventName.allCases.map(\.rawValue)))
  }

  @Test(arguments: ClientEventName.allCases)
  func eachRuleIsTheContracts(_ name: ClientEventName) throws {
    #expect(try Self.contract().rules[name.rawValue] == name.rule)
  }
}
