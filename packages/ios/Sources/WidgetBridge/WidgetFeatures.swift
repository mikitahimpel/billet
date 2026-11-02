import DesignSystem
import Foundation
import Observation
import Persistence
import Pet

/// Something the owner can switch on or off: a widget feature or a lab experiment. The raw value is
/// the key it is stored under, so the two kinds share one file without clashing.
public protocol FeatureFlag: RawRepresentable, CaseIterable, Sendable where RawValue == String {
  /// Whether the flag is on until the owner turns it off.
  var defaultOn: Bool { get }
}

extension WidgetFeature: FeatureFlag {}

/// Which features are on. Anything never switched follows its default, so a feature added later
/// does not silently turn off for someone who already has stored choices.
public struct WidgetFeatures: Equatable, Sendable {
  private var choices: [String: Bool]

  public init(choices: [WidgetFeature: Bool] = [:]) {
    self.choices = Dictionary(uniqueKeysWithValues: choices.map { ($0.key.rawValue, $0.value) })
  }

  public func isOn(_ feature: WidgetFeature) -> Bool { value(of: feature) }

  public func isOn(_ experiment: LabExperiment) -> Bool { value(of: experiment) }

  public mutating func set(_ feature: WidgetFeature, on: Bool) { choices[feature.rawValue] = on }

  public mutating func set(_ experiment: LabExperiment, on: Bool) {
    choices[experiment.rawValue] = on
  }

  private func value<Flag: FeatureFlag>(of flag: Flag) -> Bool {
    choices[flag.rawValue] ?? flag.defaultOn
  }

  /// The cat moments switched on in Labs.
  public var catMoments: Set<CatMoment> {
    let pairs: [(LabExperiment, CatMoment)] = [
      (.catCarriesNote, .carriesNote), (.catPurrs, .purrs), (.catBats, .batsAtFinger),
      (.catGreets, .greets), (.catChases, .chases),
    ]
    return Set(pairs.filter { isOn($0.0) }.map(\.1))
  }

  /// The features that are on, in declaration order.
  public var enabled: [WidgetFeature] {
    WidgetFeature.allCases.filter(isOn)
  }
}

extension WidgetFeatures: Codable {
  public init(from decoder: any Decoder) throws {
    choices = try decoder.singleValueContainer().decode([String: Bool].self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(choices)
  }
}

/// The flags as the app and its extensions share them, in a file of the App Group.
public struct WidgetFeaturesStore: Sendable {
  public static let fileName = "widget-features.json"

  private let storage: AppGroupStorage

  public init(storage: AppGroupStorage) {
    self.storage = storage
  }

  /// The App Group's store, or nil when this process has no access to the group.
  public static func appGroup() -> WidgetFeaturesStore? {
    (try? AppGroupStorage.appGroup(identifier: AppGroupStorage.billetIdentifier))
      .map(WidgetFeaturesStore.init)
  }

  /// The saved flags, or the defaults when nothing is saved or the file cannot be read.
  public func load() -> WidgetFeatures {
    (try? storage.readJSON(WidgetFeatures.self, named: Self.fileName)) ?? WidgetFeatures()
  }

  public func save(_ features: WidgetFeatures) throws(PersistenceError) {
    try storage.writeJSON(features, named: Self.fileName)
  }

  public static let roomStyleFileName = "room-style.json"

  /// The room style chosen in Labs, or `nil` when none was or the file cannot be read.
  public func loadRoomStyleOverride() -> RoomStyle? {
    (try? storage.readJSON(RoomStyle.self, named: Self.roomStyleFileName)) ?? nil
  }

  /// The saved room style, or the standard one when nothing readable is saved.
  public func loadRoomStyle() -> RoomStyle {
    loadRoomStyleOverride() ?? .standard
  }

  public func saveRoomStyle(_ style: RoomStyle) throws(PersistenceError) {
    try storage.writeJSON(style, named: Self.roomStyleFileName)
  }

  /// Forgets the Labs choice, so the room follows the pair's test, if one is running.
  public func clearRoomStyle() throws(PersistenceError) {
    try storage.remove(Self.roomStyleFileName)
  }

  public static let remoteFlagsFileName = "remote-flags.json"

  /// The variants the server last gave this pair, or none when nothing readable is saved.
  public func loadRemoteFlags() -> RemoteFlags {
    (try? storage.readJSON(RemoteFlags.self, named: Self.remoteFlagsFileName)) ?? RemoteFlags()
  }

  public func saveRemoteFlags(_ flags: RemoteFlags) throws(PersistenceError) {
    try storage.writeJSON(flags, named: Self.remoteFlagsFileName)
  }

  public static let catFileName = "cat-choice.json"

  /// The saved cat, or the standard one when nothing readable is saved.
  public func loadCat() -> CatChoice {
    (try? storage.readJSON(CatChoice.self, named: Self.catFileName)) ?? .standard
  }

  public func saveCat(_ cat: CatChoice) throws(PersistenceError) {
    try storage.writeJSON(cat, named: Self.catFileName)
  }

  public static let windowViewFileName = "window-view.json"

  /// The window view with its weather and hour chosen in Labs, or `nil` when none was or the
  /// file cannot be read.
  public func loadWindowViewOverride() -> WindowViewChoice? {
    (try? storage.readJSON(WindowViewChoice.self, named: Self.windowViewFileName)) ?? nil
  }

  /// The saved window view with its weather and hour, or the standard one when nothing readable
  /// is saved.
  public func loadWindowView() -> WindowViewChoice {
    loadWindowViewOverride() ?? .standard
  }

  public func saveWindowView(_ choice: WindowViewChoice) throws(PersistenceError) {
    try storage.writeJSON(choice, named: Self.windowViewFileName)
  }

  public static let eveningGroundFileName = "evening-ground.json"

  /// The saved ground behind every screen, or the standard one when nothing readable is saved.
  public func loadEveningGround() -> EveningGround {
    (try? storage.readJSON(EveningGround.self, named: Self.eveningGroundFileName)) ?? .standard
  }

  public func saveEveningGround(_ ground: EveningGround) throws(PersistenceError) {
    try storage.writeJSON(ground, named: Self.eveningGroundFileName)
  }

  /// Forgets the Labs choice, so the window follows the pair's flag, if one is set.
  public func clearWindowView() throws(PersistenceError) {
    try storage.remove(Self.windowViewFileName)
  }

  public static let shopkeeperFileName = "shopkeeper.json"

  /// The shopkeeper chosen in Labs, or `nil` when none was or the file cannot be read.
  public func loadShopkeeperOverride() -> Shopkeeper? {
    (try? storage.readJSON(Shopkeeper.self, named: Self.shopkeeperFileName)) ?? nil
  }

  /// The saved shopkeeper, or the standard one when nothing readable is saved.
  public func loadShopkeeper() -> Shopkeeper {
    loadShopkeeperOverride() ?? .standard
  }

  public func saveShopkeeper(_ keeper: Shopkeeper) throws(PersistenceError) {
    try storage.writeJSON(keeper, named: Self.shopkeeperFileName)
  }

  /// Forgets the Labs choice, so the shop follows the pair's flag, if one is set.
  public func clearShopkeeper() throws(PersistenceError) {
    try storage.remove(Self.shopkeeperFileName)
  }

  public static let homeVariantFileName = "home-variant.json"

  /// The layout of Home chosen in Labs, or `nil` when none was or the file cannot be read.
  public func loadHomeVariantOverride() -> HomeVariant? {
    (try? storage.readJSON(HomeVariant.self, named: Self.homeVariantFileName)) ?? nil
  }

  /// The saved layout of Home, or the standard one when nothing readable is saved.
  public func loadHomeVariant() -> HomeVariant {
    loadHomeVariantOverride() ?? .standard
  }

  public func saveHomeVariant(_ variant: HomeVariant) throws(PersistenceError) {
    try storage.writeJSON(variant, named: Self.homeVariantFileName)
  }

  /// Forgets the Labs choice, so Home follows the pair's flag, if one is set.
  public func clearHomeVariant() throws(PersistenceError) {
    try storage.remove(Self.homeVariantFileName)
  }

  public static let lightingFileName = "room-lighting.json"

  /// The lighting chosen in Labs, or `nil` when none was or the file cannot be read.
  public func loadLightingOverride() -> RoomLighting? {
    (try? storage.readJSON(RoomLighting.self, named: Self.lightingFileName)) ?? nil
  }

  /// The saved lighting of the rooms, or the standard one when nothing readable is saved.
  public func loadLighting() -> RoomLighting {
    loadLightingOverride() ?? .standard
  }

  public func saveLighting(_ lighting: RoomLighting) throws(PersistenceError) {
    try storage.writeJSON(lighting, named: Self.lightingFileName)
  }

  public static let furnitureFileName = "room-furniture.json"

  /// The saved furniture of the styled rooms, or the standard set when nothing readable is saved.
  public func loadFurniture() -> RoomFurniture {
    (try? storage.readJSON(RoomFurniture.self, named: Self.furnitureFileName)) ?? .standard
  }

  public func saveFurniture(_ furniture: RoomFurniture) throws(PersistenceError) {
    try storage.writeJSON(furniture, named: Self.furnitureFileName)
  }

  /// Forgets the Labs choice, so the rooms follow the pair's flag, if one is set.
  public func clearLighting() throws(PersistenceError) {
    try storage.remove(Self.lightingFileName)
  }

  public static let pretendHourFileName = "pretend-hour.json"

  /// The hour Home pretends it is, for trying the light of the day, or `nil` for the real clock.
  public func loadPretendHour() -> Int? {
    // The real clock is saved as -1, which no hour matches.
    let hour = (try? storage.readJSON(Int.self, named: Self.pretendHourFileName)) ?? nil
    return hour.flatMap { (0..<24).contains($0) ? $0 : nil }
  }

  public func savePretendHour(_ hour: Int?) throws(PersistenceError) {
    try storage.writeJSON(hour ?? -1, named: Self.pretendHourFileName)
  }
}

/// The flags the settings screen edits, widget features and lab experiments alike. Each change is
/// saved, then `onChange` lets the widgets redraw.
@MainActor
@Observable
public final class WidgetFeaturesModel {
  public private(set) var features: WidgetFeatures
  /// The room style chosen in Labs, or `nil` to follow the pair's test. Kept beside the flags.
  public private(set) var roomStyleOverride: RoomStyle?
  /// What the server last said about the tests this pair is in. A Labs choice beats it.
  public private(set) var remote: RemoteFlags
  /// Which cat the rooms show, and its coat. Kept beside the flags, in its own file.
  public private(set) var cat: CatChoice
  /// The window view chosen in Labs, or `nil` to follow the pair's flag. In its own file.
  public private(set) var windowViewOverride: WindowViewChoice?
  /// The layout of Home chosen in Labs, or `nil` to follow the pair's flag. In its own file.
  public private(set) var homeVariantOverride: HomeVariant?
  /// The ground behind every screen. Kept beside the flags, in its own file.
  public private(set) var eveningGround: EveningGround
  /// The hour Home pretends it is, so the light of any hour can be tried. `nil` follows the clock.
  public private(set) var pretendHour: Int?
  /// The lighting chosen in Labs, or `nil` to follow the pair's flag. In its own file.
  public private(set) var lightingOverride: RoomLighting?
  /// The shopkeeper chosen in Labs, or `nil` to follow the pair's flag. In its own file.
  public private(set) var shopkeeperOverride: Shopkeeper?
  /// Which furniture fills the styled rooms. Kept beside the flags, in its own file.
  public private(set) var furniture: RoomFurniture

  @ObservationIgnored private let store: WidgetFeaturesStore?
  @ObservationIgnored private let onChange: @MainActor () -> Void

  public init(store: WidgetFeaturesStore?, onChange: @escaping @MainActor () -> Void = {}) {
    self.store = store
    self.onChange = onChange
    features = store?.load() ?? WidgetFeatures()
    roomStyleOverride = store?.loadRoomStyleOverride()
    remote = store?.loadRemoteFlags() ?? RemoteFlags()
    cat = store?.loadCat() ?? .standard
    windowViewOverride = store?.loadWindowViewOverride()
    homeVariantOverride = store?.loadHomeVariantOverride()
    eveningGround = store?.loadEveningGround() ?? .standard
    pretendHour = store?.loadPretendHour()
    lightingOverride = store?.loadLightingOverride()
    shopkeeperOverride = store?.loadShopkeeperOverride()
    furniture = store?.loadFurniture() ?? .standard
  }

  // Each Labs setting the server can also set reads the same way: the choice made in Labs on this
  // phone, else the pair's variant if the server gave one this build has, else the standard value.

  /// How the rooms are lit.
  public var lighting: RoomLighting {
    lightingOverride ?? remote.choice(of: Experiments.roomLighting) ?? .standard
  }

  /// What the styled rooms' window looks out on. The server sets only the view, never its weather
  /// or hour.
  public var windowView: WindowViewChoice {
    windowViewOverride
      ?? remote.choice(of: Experiments.windowView, as: WindowView.self).map {
        WindowViewChoice(view: $0)
      }
      ?? .standard
  }

  /// How Home is laid out around the room.
  public var homeVariant: HomeVariant {
    homeVariantOverride ?? remote.choice(of: Experiments.homeLayout) ?? .standard
  }

  /// Who keeps the 3D shop.
  public var shopkeeper: Shopkeeper {
    shopkeeperOverride ?? remote.choice(of: Experiments.shopkeeper) ?? .standard
  }

  public func setLighting(_ lighting: RoomLighting) {
    guard lightingOverride != lighting else { return }
    lightingOverride = lighting
    try? store?.saveLighting(lighting)
  }

  public func setFurniture(_ furniture: RoomFurniture) {
    guard self.furniture != furniture else { return }
    self.furniture = furniture
    try? store?.saveFurniture(furniture)
  }

  /// Drops the Labs lighting, so the rooms follow the pair's flag.
  public func followTheLightingTest() {
    guard lightingOverride != nil else { return }
    lightingOverride = nil
    try? store?.clearLighting()
  }

  public func setShopkeeper(_ keeper: Shopkeeper) {
    guard shopkeeperOverride != keeper else { return }
    shopkeeperOverride = keeper
    try? store?.saveShopkeeper(keeper)
  }

  /// Drops the Labs shopkeeper, so the shop follows the pair's flag.
  public func followTheShopkeeperTest() {
    guard shopkeeperOverride != nil else { return }
    shopkeeperOverride = nil
    try? store?.clearShopkeeper()
  }

  public func setPretendHour(_ hour: Int?) {
    let hour = hour.flatMap { (0..<24).contains($0) ? $0 : nil }
    guard pretendHour != hour else { return }
    pretendHour = hour
    try? store?.savePretendHour(hour)
  }

  public func setHomeVariant(_ variant: HomeVariant) {
    guard homeVariantOverride != variant else { return }
    homeVariantOverride = variant
    try? store?.saveHomeVariant(variant)
  }

  /// Drops the Labs layout, so Home follows the pair's flag.
  public func followTheHomeVariantTest() {
    guard homeVariantOverride != nil else { return }
    homeVariantOverride = nil
    try? store?.clearHomeVariant()
  }

  /// How a scene with more than one room dresses it: the Labs choice, else the variant of the
  /// pair's `home-direction` test if one is running and this build has it, else the standard room.
  /// Offline, with nothing saved, or with the test switched off, this is what the app always did.
  public var roomStyle: RoomStyle {
    roomStyleOverride
      ?? remote.variant(of: Experiments.homeDirection).flatMap(
        RoomStyle.init(homeDirectionVariant:))
      ?? .standard
  }

  public func setRoomStyle(_ style: RoomStyle) {
    guard roomStyleOverride != style else { return }
    roomStyleOverride = style
    try? store?.saveRoomStyle(style)
  }

  public func setWindowView(_ choice: WindowViewChoice) {
    guard windowViewOverride != choice else { return }
    windowViewOverride = choice
    try? store?.saveWindowView(choice)
  }

  public func setEveningGround(_ ground: EveningGround) {
    guard eveningGround != ground else { return }
    eveningGround = ground
    try? store?.saveEveningGround(ground)
    // The widgets stand on the same ground.
    onChange()
  }

  /// Drops the Labs view and its weather and hour, so the window follows the pair's flag.
  public func followTheWindowViewTest() {
    guard windowViewOverride != nil else { return }
    windowViewOverride = nil
    try? store?.clearWindowView()
  }

  /// Drops the Labs choice, so the room follows the pair's test.
  public func followTheTest() {
    guard roomStyleOverride != nil else { return }
    roomStyleOverride = nil
    try? store?.clearRoomStyle()
  }

  /// Takes the server's latest answer in place of the one held, and keeps it for next time.
  public func setRemote(_ flags: RemoteFlags) {
    guard remote != flags else { return }
    remote = flags
    try? store?.saveRemoteFlags(flags)
    onChange()
  }

  public func setCat(_ choice: CatChoice) {
    guard cat != choice else { return }
    cat = choice
    try? store?.saveCat(choice)
  }

  public func isOn(_ feature: WidgetFeature) -> Bool { features.isOn(feature) }

  public func isOn(_ experiment: LabExperiment) -> Bool { features.isOn(experiment) }

  public func set(_ feature: WidgetFeature, on: Bool) {
    guard features.isOn(feature) != on else { return }
    features.set(feature, on: on)
    changed()
  }

  public func set(_ experiment: LabExperiment, on: Bool) {
    guard features.isOn(experiment) != on else { return }
    features.set(experiment, on: on)
    changed()
  }

  private func changed() {
    try? store?.save(features)
    onChange()
  }
}
