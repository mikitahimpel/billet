import Foundation
import Pet
import Testing

@testable import WidgetBridge

/// The Labs settings the server can set: each case is a variant, and the server's registry lists
/// the same ones.
@Suite struct RemoteChoiceTests {
  // MARK: case names and variant ids

  @Test(arguments: RoomLighting.allCases)
  func everyLightingIsAVariantAndBack(_ lighting: RoomLighting) {
    #expect(Experiments.roomLighting.variants.contains(lighting.remoteVariant))
    #expect(RoomLighting(remoteVariant: lighting.remoteVariant) == lighting)
  }

  @Test(arguments: WindowView.allCases)
  func everyWindowViewIsAVariantAndBack(_ view: WindowView) {
    #expect(Experiments.windowView.variants.contains(view.remoteVariant))
    #expect(WindowView(remoteVariant: view.remoteVariant) == view)
  }

  @Test(arguments: HomeVariant.allCases)
  func everyHomeVariantIsAVariantAndBack(_ variant: HomeVariant) {
    #expect(Experiments.homeLayout.variants.contains(variant.remoteVariant))
    #expect(HomeVariant(remoteVariant: variant.remoteVariant) == variant)
  }

  @Test(arguments: Shopkeeper.allCases)
  func everyShopkeeperIsAVariantAndBack(_ keeper: Shopkeeper) {
    #expect(Experiments.shopkeeper.variants.contains(keeper.remoteVariant))
    #expect(Shopkeeper(remoteVariant: keeper.remoteVariant) == keeper)
  }

  @Test func anUnknownVariantIsNoChoice() {
    #expect(RoomLighting(remoteVariant: "disco") == nil)
    #expect(RoomLighting(remoteVariant: "amberLantern") == nil)
    #expect(WindowView(remoteVariant: "moon-base") == nil)
    #expect(HomeVariant(remoteVariant: "") == nil)
    #expect(Shopkeeper(remoteVariant: "Fox") == nil)
  }

  @Test func theVariantsAreTheCaseNamesInKebabCase() {
    #expect(
      Experiments.roomLighting.variants == [
        "off", "amber-lantern", "fairy-lights", "golden-hour", "neon-night", "candle",
      ])
    #expect(
      Experiments.windowView.variants == [
        "suburb-night", "rainy-suburb", "snowy-december", "summer-cul-de-sac", "dorm-quad",
        "fire-escape", "pink-dusk",
      ])
    #expect(
      Experiments.homeLayout.variants == [
        "classic", "immersive", "living-window", "night-and-day",
      ])
    #expect(Experiments.shopkeeper.variants == ["teddy", "human"])
  }

  @Test func everyRemoteSettingIsListed() {
    let keys = Set(Experiments.all.map(\.key))
    #expect(
      keys == ["room-lighting", "window-view", "home-layout", "shopkeeper"])
  }

  @Test func aChoiceTheServerGaveIsRead() {
    let flags = RemoteFlags(assignments: [
      "room-lighting": "neon-night", "window-view": "summer-cul-de-sac",
      "home-layout": "night-and-day", "shopkeeper": "human",
    ])
    #expect(flags.choice(of: Experiments.roomLighting) == RoomLighting.neonNight)
    #expect(flags.choice(of: Experiments.windowView) == WindowView.summerCulDeSac)
    #expect(flags.choice(of: Experiments.homeLayout) == HomeVariant.nightAndDay)
    #expect(flags.choice(of: Experiments.shopkeeper) == Shopkeeper.human)
  }

  // MARK: the server's registry

  /// The `key:` and variant ids of each entry in the server's `registry`.
  static func serverRegistry() throws -> [String: Set<String>] {
    let file = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "packages/backend/flags/src/experiments.ts")
    let source = try String(contentsOf: file, encoding: .utf8)
    let registry = try #require(source.firstRange(of: "export const registry")).upperBound
    let body = source[registry...]
    let entry = #/key:\s*"([^"]+)"[\s\S]*?variants:\s*\{([^}]*)\}/#
    let variant = #/(?:"([^"]+)"|([A-Za-z0-9_-]+))\s*:\s*\d+/#
    var result: [String: Set<String>] = [:]
    for match in body.matches(of: entry) {
      let ids = match.2.matches(of: variant).map { String($0.1 ?? $0.2 ?? "") }
      result[String(match.1)] = Set(ids)
    }
    return result
  }

  @Test func theServerListsTheParsedEntries() throws {
    #expect(try Self.serverRegistry().count >= Experiments.all.count)
  }

  @Test(arguments: Experiments.all)
  func theServerHasTheSameVariants(_ experiment: Experiment) throws {
    let server = try Self.serverRegistry()
    #expect(server[experiment.key] == experiment.variants)
  }
}
