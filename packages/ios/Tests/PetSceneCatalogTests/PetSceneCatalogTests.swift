import Foundation
import Persistence
import Pet
import PetScene
import PetSceneCatalog
import SwiftUI
import Testing

@MainActor
private struct StubScene: PetScene {
  let id: String
  var title: String { id }
  var poses: [PetPose: Data] = [:]

  func makeView(world: PetWorld, onEvent: @escaping @MainActor (PetSceneEvent) -> Void) -> AnyView {
    AnyView(EmptyView())
  }

  func posePNG(_ pose: PetPose) -> Data? { poses[pose] }
}

@Suite("PetSceneCatalog")
@MainActor
struct PetSceneCatalogTests {
  private let defaults: UserDefaults
  private let directory: URL
  private let storage: AppGroupStorage

  init() {
    let name = "PetSceneCatalogTests-\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: name)!
    directory = FileManager.default.temporaryDirectory.appending(path: name)
    storage = .directory(directory)
  }

  private func catalog(_ scenes: [any PetScene]) -> PetSceneCatalog {
    PetSceneCatalog(scenes: scenes, defaults: defaults, poses: storage)
  }

  @Test func firstSceneIsTheDefault() {
    #expect(catalog([StubScene(id: "a"), StubScene(id: "b")]).selectedID == "a")
  }

  @Test func noScenesMeansNoSelection() {
    let empty = catalog([])
    #expect(empty.selectedID == nil)
    #expect(empty.selected == nil)
  }

  @Test func choiceSurvivesARestart() {
    catalog([StubScene(id: "a"), StubScene(id: "b")]).select("b")
    #expect(catalog([StubScene(id: "a"), StubScene(id: "b")]).selected?.id == "b")
  }

  @Test func unlinkedSceneFallsBackAndItsChoiceIsKept() {
    catalog([StubScene(id: "a"), StubScene(id: "b")]).select("b")
    #expect(catalog([StubScene(id: "a")]).selectedID == "a")
    #expect(catalog([StubScene(id: "a"), StubScene(id: "b")]).selectedID == "b")
  }

  @Test func unknownIDIsIgnored() {
    let scenes = catalog([StubScene(id: "a")])
    scenes.select("gone")
    #expect(scenes.selectedID == "a")
    #expect(defaults.string(forKey: PetSceneCatalog.choiceKey) == nil)
  }

  @Test func poseFilesFollowTheChoice() throws {
    let a = StubScene(
      id: "a", poses: [.sleeping: Data([1]), .proud: Data([2])])
    let b = StubScene(id: "b", poses: [.sleeping: Data([3])])
    let scenes = catalog([a, b])
    #expect(try storage.read(PetPose.sleeping.fileName) == Data([1]))
    #expect(try storage.read(PetPose.proud.fileName) == Data([2]))
    scenes.select("b")
    #expect(try storage.read(PetPose.sleeping.fileName) == Data([3]))
    #expect(try storage.read(PetPose.proud.fileName) == nil)
  }

  @Test func publishingNotifiesOnStartAndOnChange() {
    var published = 0
    let scenes = PetSceneCatalog(
      scenes: [StubScene(id: "a"), StubScene(id: "b")], defaults: defaults, poses: storage,
      onPosesPublished: { published += 1 })
    #expect(published == 1)
    scenes.select("a")
    #expect(published == 1)
    scenes.select("b")
    #expect(published == 2)
  }

  @Test func missingAppGroupStillSelects() {
    let scenes = PetSceneCatalog(
      scenes: [StubScene(id: "a"), StubScene(id: "b")], defaults: defaults, poses: nil)
    scenes.select("b")
    #expect(scenes.selectedID == "b")
  }
}
