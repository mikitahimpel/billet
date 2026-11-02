import Foundation
import Persistence
import Pet
import Testing
import Transport
import WidgetBridge
import Wire

@testable import FeatureHome

@Suite @MainActor struct FlagsRefresherTests {
  private func storage() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }

  private func labs(_ storage: AppGroupStorage) -> WidgetFeaturesModel {
    WidgetFeaturesModel(store: WidgetFeaturesStore(storage: storage))
  }

  private func api(_ result: Result<FlagsResponse, TransportError>) -> APIClient {
    var client = APIClient.offline
    client.flags = { () async throws(TransportError) in try result.get() }
    return client
  }

  private func answer(_ pairs: (String, String)...) -> FlagsResponse {
    FlagsResponse(flags: pairs.map { FlagAssignment(key: $0.0, variant: $0.1) })
  }

  @Test func theServersVariantsAreKeptAndChooseTheRoom() async {
    let labs = labs(storage())
    await FlagsRefresher(api: api(.success(answer(("home-direction", "sunset-lamp")))), labs: labs)
      .refresh()
    #expect(labs.roomStyle == .sunsetLamp)
  }

  @Test func theAnswerIsKeptForTheNextLaunch() async {
    let storage = storage()
    await FlagsRefresher(
      api: api(.success(answer(("home-direction", "window-seat")))), labs: labs(storage)
    ).refresh()
    #expect(labs(storage).roomStyle == .windowSeat)
  }

  @Test func offlineKeepsTheLastAnswerRatherThanLosingIt() async {
    let labs = labs(storage())
    await FlagsRefresher(api: api(.success(answer(("home-direction", "window-seat")))), labs: labs)
      .refresh()
    await FlagsRefresher(api: api(.failure(.network("offline"))), labs: labs).refresh()
    #expect(labs.roomStyle == .windowSeat)
  }

  @Test(arguments: [
    TransportError.api(.unauthorized), .api(.unavailable), .status(500), .network("x"),
  ])
  func anyFailureChangesNothing(_ error: TransportError) async {
    let labs = labs(storage())
    await FlagsRefresher(api: api(.failure(error)), labs: labs).refresh()
    #expect(labs.remote.isEmpty)
    #expect(labs.roomStyle == .standard)
  }

  @Test func anExperimentTheServerStopsListingFallsAway() async {
    let labs = labs(storage())
    await FlagsRefresher(api: api(.success(answer(("home-direction", "window-seat")))), labs: labs)
      .refresh()
    await FlagsRefresher(api: api(.success(answer())), labs: labs).refresh()
    #expect(labs.remote.isEmpty)
    #expect(labs.roomStyle == .standard)
  }

  @Test func aVariantThisBuildDoesNotHaveChangesNothingVisible() async {
    let labs = labs(storage())
    await FlagsRefresher(api: api(.success(answer(("home-direction", "attic")))), labs: labs)
      .refresh()
    #expect(labs.roomStyle == .standard)
  }

  @Test func theFirstOfARepeatedKeyWins() async {
    let labs = labs(storage())
    await FlagsRefresher(
      api: api(
        .success(answer(("home-direction", "window-seat"), ("home-direction", "sunset-lamp")))),
      labs: labs
    ).refresh()
    #expect(labs.roomStyle == .windowSeat)
  }

  @Test func aLabsChoiceStillBeatsTheServer() async {
    let labs = labs(storage())
    labs.setRoomStyle(.nooki)
    await FlagsRefresher(api: api(.success(answer(("home-direction", "window-seat")))), labs: labs)
      .refresh()
    #expect(labs.roomStyle == .nooki)
  }

  @Test func leavingThePairForgetsItsVariants() async {
    let labs = labs(storage())
    let refresher = FlagsRefresher(
      api: api(.success(answer(("home-direction", "window-seat")))), labs: labs)
    await refresher.refresh()
    refresher.forget()
    #expect(labs.remote.isEmpty)
    #expect(labs.roomStyle == .standard)
  }
}
