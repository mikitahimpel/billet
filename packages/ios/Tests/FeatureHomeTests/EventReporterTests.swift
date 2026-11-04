import Foundation
import Persistence
import Pet
import Testing
import Transport
import WidgetBridge
import Wire

@testable import FeatureHome

@Suite @MainActor struct EventReporterTests {
  /// Records what the server was sent, and can be told to fail or to refuse what it gets.
  final class Server: @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [[ClientEvent]] = []
    private var failure: TransportError?
    private var attempts = 0

    var sent: [[ClientEvent]] { lock.withLock { batches } }
    var tries: Int { lock.withLock { attempts } }
    func setFailing(_ value: Bool) { lock.withLock { failure = value ? .network("offline") : nil } }
    func fail(with error: TransportError?) { lock.withLock { failure = error } }

    var api: APIClient {
      var client = APIClient.offline
      client.reportEvents = { [self] (events) async throws(TransportError) in
        let refused = lock.withLock { () -> TransportError? in
          attempts += 1
          if let failure { return failure }
          batches.append(events)
          return nil
        }
        if let refused { throw refused }
      }
      return client
    }
  }

  /// A switch the test flips, standing in for the service status.
  final class Switch {
    var on = true
  }

  /// A clock the test moves.
  final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000_000)
  }

  private func storage() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }

  private let opened = ClientEvent(.appOpened)

  @Test func theAppOpeningIsCountedOncePerLaunch() async {
    let server = Server()
    let reporter = EventReporter(api: server.api, storage: storage())
    reporter.appOpened()
    reporter.appOpened()
    await reporter.flush()
    #expect(server.sent == [[opened]])
  }

  @Test func eachWidgetKindIsCountedOnceEvenAcrossLaunches() async {
    let server = Server()
    let storage = storage()
    let first = EventReporter(api: server.api, storage: storage)
    first.widgetsAdded(kinds: ["LatestNote"])
    first.widgetsAdded(kinds: ["LatestNote"])
    await first.flush()
    let second = EventReporter(api: server.api, storage: storage)
    second.widgetsAdded(kinds: ["LatestNote", "Pictures"])
    await second.flush()
    #expect(
      server.sent == [
        [ClientEvent(.widgetAdded, detail: "LatestNote")],
        [ClientEvent(.widgetAdded, detail: "Pictures")],
      ])
  }

  @Test func aWidgetKindThatCannotBeADetailIsMadeOne() async {
    let server = Server()
    let reporter = EventReporter(api: server.api, storage: storage())
    reporter.widgetsAdded(kinds: ["Pet_Pose.v2", "2up"])
    await reporter.flush()
    let kinds = [ClientEvent(.widgetAdded), ClientEvent(.widgetAdded, detail: "Pet-Pose-v2")]
    #expect(server.sent == [kinds])
  }

  @Test func noWidgetIsNotCounted() async {
    let server = Server()
    let reporter = EventReporter(api: server.api, storage: storage())
    reporter.widgetsAdded(kinds: [])
    await reporter.flush()
    #expect(server.sent.isEmpty)
  }

  @Test func whatCouldNotBeSentWaitsAndGoesLaterInOrder() async {
    let server = Server()
    let reporter = EventReporter(api: server.api, storage: storage())
    server.setFailing(true)
    reporter.appOpened()
    reporter.record(.shopOpened)
    await reporter.flush()
    #expect(server.sent.isEmpty)
    #expect(reporter.waiting == [opened, ClientEvent(.shopOpened)])
    server.setFailing(false)
    await reporter.flush()
    #expect(server.sent == [[opened, ClientEvent(.shopOpened)]])
    #expect(reporter.waiting.isEmpty)
  }

  @Test func aBatchTheServerRefusesIsDroppedAndTheRestStillGo() async {
    let server = Server()
    let reporter = EventReporter(api: server.api, storage: storage())
    for _ in 0..<(ReportEventsRequest.maxEvents + 3) { reporter.record(.shopOpened) }
    server.fail(with: .status(400))
    await reporter.flush()
    #expect(reporter.waiting.isEmpty)
    #expect(server.tries == 2)

    reporter.record(.streakOpened)
    server.fail(with: .api(.invalidRequest))
    await reporter.flush()
    #expect(reporter.waiting.isEmpty)
    #expect(server.sent.isEmpty)
  }

  @Test(arguments: [
    TransportError.network("offline"), .status(500), .status(429), .api(.unauthorized),
    .api(.unavailable), .maintenance(.normal), .decoding,
  ])
  func anyOtherFailureKeepsTheBatch(_ error: TransportError) async {
    let server = Server()
    let reporter = EventReporter(api: server.api, storage: storage())
    reporter.appOpened()
    server.fail(with: error)
    await reporter.flush()
    #expect(reporter.waiting == [opened])
  }

  @Test func whatWaitsSurvivesARestart() async {
    let server = Server()
    let storage = storage()
    server.setFailing(true)
    let first = EventReporter(api: server.api, storage: storage)
    first.appOpened()
    first.record(.shopItemBought("treat-fish", price: 3))
    await first.flush()
    server.setFailing(false)
    let second = EventReporter(api: server.api, storage: storage)
    await second.flush()
    let bought = ClientEvent(.shopItemBought, detail: "treat-fish", value: 3)
    #expect(server.sent == [[opened, bought]])
  }

  @Test func anOutboxSavedAsBareNamesIsStillSent() async throws {
    let server = Server()
    let storage = storage()
    try storage.write(
      "pending-events.json", Data(#"{"waiting":["AppOpened","WidgetAdded"]}"#.utf8))
    let reporter = EventReporter(api: server.api, storage: storage)
    #expect(reporter.waiting == [opened, ClientEvent(.widgetAdded)])
    await reporter.flush()
    #expect(server.sent == [[opened, ClientEvent(.widgetAdded)]])
  }

  @Test func anOutboxThatCannotBeReadIsDropped() async throws {
    let server = Server()
    let storage = storage()
    try storage.write("pending-events.json", Data(#"{"waiting":["NoteSent"]}"#.utf8))
    let reporter = EventReporter(api: server.api, storage: storage)
    #expect(reporter.waiting.isEmpty)
    reporter.appOpened()
    await reporter.flush()
    #expect(server.sent == [[opened]])
  }

  @Test func aSentEventIsNeverSentTwice() async {
    let server = Server()
    let reporter = EventReporter(api: server.api, storage: storage())
    reporter.appOpened()
    await reporter.flush()
    await reporter.flush()
    #expect(server.sent.count == 1)
  }

  @Test func aLongWaitIsSentInRequestsThatFit() async {
    var outbox = EventOutbox()
    for _ in 0..<45 { outbox.add(opened) }
    var sizes: [Int] = []
    while !outbox.batch.isEmpty {
      sizes.append(outbox.batch.count)
      outbox.sent(outbox.batch.count)
    }
    #expect(sizes == [20, 20, 5])
  }

  @Test func theWaitingListIsCappedAndDropsTheOldest() {
    var outbox = EventOutbox()
    outbox.add(ClientEvent(.widgetAdded))
    for _ in 0..<EventOutbox.limit { outbox.add(opened) }
    #expect(outbox.waiting.count == EventOutbox.limit)
    #expect(!outbox.waiting.contains(ClientEvent(.widgetAdded)))
  }

  @Test func signingOutForgetsWhatWaitedAndWhatWasCountedOnce() async {
    let server = Server()
    let storage = storage()
    let reporter = EventReporter(api: server.api, storage: storage)
    server.setFailing(true)
    reporter.appOpened()
    reporter.widgetsAdded(kinds: ["Actions"])
    await reporter.flush()
    reporter.discard()
    server.setFailing(false)
    await reporter.flush()
    #expect(server.sent.isEmpty)
    reporter.widgetsAdded(kinds: ["Actions"])
    await reporter.flush()
    #expect(server.sent == [[ClientEvent(.widgetAdded, detail: "Actions")]])
  }

  @Test func onlyNamesAndCatalogueIDsAreStoredOnDevice() throws {
    let storage = storage()
    let reporter = EventReporter(api: Server().api, storage: storage)
    reporter.appOpened()
    reporter.record(.catChosen(.idolIlya))
    let data = try #require(try storage.read("pending-events.json"))
    let saved = try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    let expected: NSDictionary = [
      "waiting": [["name": "AppOpened"], ["name": "CatChosen", "detail": "idolIlya"]]
    ]
    #expect(saved == expected)
  }

  // MARK: the switch

  @Test func switchedOffNothingIsRecordedOrSent() async {
    let server = Server()
    let analytics = Switch()
    analytics.on = false
    let reporter = EventReporter(
      api: server.api, storage: storage(), isEnabled: { analytics.on })
    reporter.appOpened()
    reporter.widgetsAdded(kinds: ["Pictures"])
    reporter.record(.catPetted)
    await reporter.flush()
    #expect(reporter.waiting.isEmpty)
    #expect(server.tries == 0)

    analytics.on = true
    reporter.widgetsAdded(kinds: ["Pictures"])
    await reporter.flush()
    #expect(server.sent == [[ClientEvent(.widgetAdded, detail: "Pictures")]])
  }

  @Test func switchingOffDropsWhatWasWaiting() async throws {
    let server = Server()
    let storage = storage()
    let analytics = Switch()
    let reporter = EventReporter(api: server.api, storage: storage, isEnabled: { analytics.on })
    server.setFailing(true)
    reporter.appOpened()
    reporter.record(.shopOpened)
    await reporter.flush()
    #expect(reporter.waiting.count == 2)

    analytics.on = false
    reporter.analyticsChanged()
    #expect(reporter.waiting.isEmpty)
    let saved = try #require(try storage.read("pending-events.json"))
    #expect(String(decoding: saved, as: UTF8.self) == #"{"waiting":[]}"#)
    server.setFailing(false)
    await reporter.flush()
    #expect(server.tries == 1)
  }

  // MARK: what the views report

  @Test func eachViewEventIsSentWithItsDetail() async {
    let server = Server()
    let reporter = EventReporter(api: server.api, storage: storage())
    let events: [AppEvent] = [
      .catFed(.treat), .catFed(.food), .catPlayed(.laser), .catPlayed(nil), .trickDone(.highFive),
      .temperamentShown(.sleepyhead), .noteOpened(.app), .roomItemPlaced("furniture-rug"),
      .roomCustomised("wall-sage"), .shopItemBought("furniture-tower", price: 36),
      .streakMilestoneSeen(.everglow), .widgetButtonTapped(.treat),
      .signInPromptAnswered(accepted: false),
    ]
    for event in events { reporter.record(event) }
    await reporter.flush()
    #expect(
      server.sent == [
        [
          ClientEvent(.catFed, detail: "treat"), ClientEvent(.catFed, detail: "food"),
          ClientEvent(.catPlayed, detail: "laser"), ClientEvent(.catPlayed),
          ClientEvent(.trickDone, detail: "highFive"),
          ClientEvent(.temperamentShown, detail: "sleepyhead"),
          ClientEvent(.noteOpened, detail: "app"),
          ClientEvent(.roomItemPlaced, detail: "furniture-rug"),
          ClientEvent(.roomCustomised, detail: "wall-sage"),
          ClientEvent(.shopItemBought, detail: "furniture-tower", value: 36),
          ClientEvent(.streakMilestoneSeen, detail: "everglow"),
          ClientEvent(.widgetButtonTapped, detail: "treat"),
          ClientEvent(.signInPromptAnswered, detail: "dismissed"),
        ]
      ])
  }

  @Test func everyCatalogueIDTheViewsReportIsAValidDetail() {
    var events: [AppEvent] =
      CatToy.allCases.map { .catPlayed($0) } + CatTrick.allCases.map(AppEvent.trickDone)
      + CatModel.allCases.map(AppEvent.catChosen)
      + CatTemperament.allCases.map(AppEvent.temperamentShown)
      + FlameStage.allCases.map(AppEvent.streakMilestoneSeen)
    for item in ShopCatalog.standard.items {
      events += [
        .roomItemPlaced(item.id), .roomItemMoved(item.id), .roomItemPutAway(item.id),
        .roomCustomised(item.id), .shopItemViewed(item.id),
        .shopItemBought(item.id, price: item.price), .shopOfferViewed("deal-\(item.id)"),
        .shopGiftSent(item.id, price: item.price),
        .shopPurchaseUndone(item.id, stamps: item.price),
      ]
    }
    for bundle in ShopBundle.all {
      events += [
        .shopOfferViewed(bundle.id), .shopBundleBought(bundle.id, price: 30),
        .shopPurchaseUndone(bundle.id, stamps: 30),
      ]
    }
    events += [.shopDailyGiftClaimed(.stamps(15)), .shopDailyGiftClaimed(.item("treat-milk"))]
    for event in events {
      #expect(ClientEvent(reporting: event).problem == nil, "\(event)")
    }
  }

  @Test func repeatedPettingWithinAMomentCountsOnce() async {
    let server = Server()
    let clock = Clock()
    let reporter = EventReporter(api: server.api, storage: storage(), now: { clock.now })
    reporter.record(.catPetted)
    clock.now += 3
    reporter.record(.catPetted)
    reporter.record(.shopItemViewed("treat-fish"))
    reporter.record(.shopItemViewed("treat-milk"))
    reporter.record(.shopItemViewed("treat-fish"))
    clock.now += EventReporter.repeatGap
    reporter.record(.catPetted)
    reporter.record(.shopOpened)
    reporter.record(.shopOpened)
    await reporter.flush()
    #expect(
      server.sent == [
        [
          ClientEvent(.catPetted), ClientEvent(.shopItemViewed, detail: "treat-fish"),
          ClientEvent(.shopItemViewed, detail: "treat-milk"), ClientEvent(.catPetted),
          ClientEvent(.shopOpened), ClientEvent(.shopOpened),
        ]
      ])
  }

  // MARK: the app model

  private func model(
    server: Server, status: ServiceStatusModel, kinds: Set<String> = []
  ) -> RealAppModel {
    RealAppModel(
      api: server.api,
      accounts: AccountStore(load: { nil }, save: { _, _ in }, setPaired: { _, _ in }, clear: {}),
      keys: AccountKeyStore(loadOrCreate: { "k" }, clear: {}),
      baseURL: URL(fileURLWithPath: "/"),
      labs: WidgetFeaturesModel(store: nil),
      eventStorage: storage(),
      widgetKinds: { kinds },
      serviceStatus: status)
  }

  @Test func leavingTheFrontSendsWhatWaits() async {
    let server = Server()
    let model = model(server: server, status: ServiceStatusModel(appVersion: nil, fetch: nil))
    model.events(.streakOpened)
    #expect(server.sent.isEmpty)
    await model.enteredBackground()
    #expect(server.sent == [[ClientEvent(.streakOpened)]])
  }

  @Test func comingToTheFrontCountsTheOpeningAndEachWidgetKind() async {
    let server = Server()
    let model = model(
      server: server, status: ServiceStatusModel(appVersion: nil, fetch: nil),
      kinds: ["Pictures", "Actions"])
    await model.becameActive()
    await model.becameActive()
    #expect(
      server.sent == [
        [
          opened, ClientEvent(.widgetAdded, detail: "Actions"),
          ClientEvent(.widgetAdded, detail: "Pictures"),
        ]
      ])
  }

  @Test func theServedSwitchStopsReportingAndDropsWhatWaits() async {
    let server = Server()
    let status = ServiceStatusModel(appVersion: nil, fetch: nil)
    let model = model(server: server, status: status)
    server.setFailing(true)
    await model.becameActive()
    model.events(.shopOpened)

    status.received(
      AppStatus(maintenance: MaintenanceStatus(active: false), analytics: .init(enabled: false)))
    #expect(!status.analyticsEnabled)
    model.analyticsChanged()
    server.setFailing(false)
    model.events(.catPetted)
    await model.enteredBackground()
    #expect(server.sent.isEmpty)

    status.received(.normal)
    model.events(.streakOpened)
    await model.enteredBackground()
    #expect(server.sent == [[ClientEvent(.streakOpened)]])
  }
}

@Suite struct RoomLayoutEventsTests {
  @Test func placingMovingAndPuttingAwayAreToldApart() {
    let old = RoomLayout(placements: [
      .init(id: "a", item: "furniture-rug", x: 0, z: 0),
      .init(id: "b", item: "furniture-lamp", x: 1, z: 1),
      .init(id: "c", item: "furniture-tower", x: 2, z: 2),
    ])
    let new = RoomLayout(placements: [
      .init(id: "a", item: "furniture-rug", x: 0, z: 0),
      .init(id: "b", item: "furniture-lamp", x: 1, z: 1, yaw: 1),
      .init(id: "d", item: "furniture-yarn", x: 3, z: 3),
    ])
    #expect(
      RoomLayoutEvents.between(old, new) == [
        .roomItemMoved("furniture-lamp"), .roomItemPlaced("furniture-yarn"),
        .roomItemPutAway("furniture-tower"),
      ])
  }

  @Test func aNewWallOrFloorCustomisesTheRoom() {
    let old = RoomLayout()
    let new = RoomLayout(wall: "wall-sage")
    #expect(RoomLayoutEvents.between(old, new) == [.roomCustomised("wall-sage")])
    #expect(RoomLayoutEvents.between(new, old).isEmpty)
  }
}
