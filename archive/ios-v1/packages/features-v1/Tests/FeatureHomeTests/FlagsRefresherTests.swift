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

  @Test func theServersVariantsAreKeptAndChooseTheLight() async {
    let labs = labs(storage())
    await FlagsRefresher(api: api(.success(answer(("room-lighting", "golden-hour")))), labs: labs)
      .refresh()
    #expect(labs.lighting == .goldenHour)
  }

  @Test func theAnswerIsKeptForTheNextLaunch() async {
    let storage = storage()
    await FlagsRefresher(
      api: api(.success(answer(("room-lighting", "fairy-lights")))), labs: labs(storage)
    ).refresh()
    #expect(labs(storage).lighting == .fairyLights)
  }

  @Test func offlineKeepsTheLastAnswerRatherThanLosingIt() async {
    let labs = labs(storage())
    await FlagsRefresher(api: api(.success(answer(("room-lighting", "fairy-lights")))), labs: labs)
      .refresh()
    await FlagsRefresher(api: api(.failure(.network("offline"))), labs: labs).refresh()
    #expect(labs.lighting == .fairyLights)
  }

  @Test(arguments: [
    TransportError.api(.unauthorized), .api(.unavailable), .status(500), .network("x"),
  ])
  func anyFailureChangesNothing(_ error: TransportError) async {
    let labs = labs(storage())
    await FlagsRefresher(api: api(.failure(error)), labs: labs).refresh()
    #expect(labs.remote.isEmpty)
    #expect(labs.lighting == .standard)
  }

  @Test func anExperimentTheServerStopsListingFallsAway() async {
    let labs = labs(storage())
    await FlagsRefresher(api: api(.success(answer(("room-lighting", "fairy-lights")))), labs: labs)
      .refresh()
    await FlagsRefresher(api: api(.success(answer())), labs: labs).refresh()
    #expect(labs.remote.isEmpty)
    #expect(labs.lighting == .standard)
  }

  @Test func aVariantThisBuildDoesNotHaveChangesNothingVisible() async {
    let labs = labs(storage())
    await FlagsRefresher(api: api(.success(answer(("room-lighting", "disco")))), labs: labs)
      .refresh()
    #expect(labs.lighting == .standard)
  }

  @Test func theFirstOfARepeatedKeyWins() async {
    let labs = labs(storage())
    await FlagsRefresher(
      api: api(
        .success(answer(("room-lighting", "fairy-lights"), ("room-lighting", "golden-hour")))),
      labs: labs
    ).refresh()
    #expect(labs.lighting == .fairyLights)
  }

  @Test func aLabsChoiceStillBeatsTheServer() async {
    let labs = labs(storage())
    labs.setLighting(.candle)
    await FlagsRefresher(api: api(.success(answer(("room-lighting", "fairy-lights")))), labs: labs)
      .refresh()
    #expect(labs.lighting == .candle)
  }

  @Test func leavingThePairForgetsItsVariants() async {
    let labs = labs(storage())
    let refresher = FlagsRefresher(
      api: api(.success(answer(("room-lighting", "fairy-lights")))), labs: labs)
    await refresher.refresh()
    refresher.forget()
    #expect(labs.remote.isEmpty)
    #expect(labs.lighting == .standard)
  }
}
