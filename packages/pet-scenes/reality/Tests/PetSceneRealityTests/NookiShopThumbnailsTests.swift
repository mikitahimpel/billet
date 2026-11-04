import Foundation
import Pet
import Testing

@testable import PetSceneReality

@MainActor
@Suite struct NookiShopThumbnailsTests {
  private let folder = FileManager.default.temporaryDirectory.appending(
    path: "thumbs-\(UUID().uuidString)", directoryHint: .isDirectory)

  private var view: ShopItem {
    get throws {
      try #require(ShopCatalog.standard.items(on: .views).first)
    }
  }

  @Test func aViewIsDrawnOnceAndReadBackOnTheNextLaunch() async throws {
    let item = try view
    let first = NookiShopThumbnails(folder: folder, makeStage: { nil })
    let image = try #require(await first.image(of: item, side: 60, scale: 2))
    #expect(image.width == 120)
    let files = try FileManager.default.contentsOfDirectory(atPath: folder.path())
    #expect(files == ["\(item.id)-120.png"])
    let next = NookiShopThumbnails(folder: folder, makeStage: { nil })
    let read = try #require(await next.image(of: item, side: 60, scale: 2))
    #expect(read.width == 120)
  }

  @Test func aStillIsNeverLargerThanTheCap() async throws {
    let image = try #require(
      await NookiShopThumbnails(folder: nil, makeStage: { nil }).image(
        of: try view, side: 400, scale: 3))
    #expect(image.width == NookiShopThumbnails.largest)
  }

  @Test func withoutARendererAPieceHasNoStill() async throws {
    let piece = try #require(ShopCatalog.standard.items.first(where: \.isPlaceable))
    let thumbnails = NookiShopThumbnails(folder: nil, makeStage: { nil })
    #expect(await thumbnails.image(of: piece, side: 60, scale: 2) == nil)
  }
}
