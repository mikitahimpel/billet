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

  /// The saved room style, or the standard one when nothing readable is saved.
  public func loadRoomStyle() -> RoomStyle {
    (try? storage.readJSON(RoomStyle.self, named: Self.roomStyleFileName)) ?? .standard
  }

  public func saveRoomStyle(_ style: RoomStyle) throws(PersistenceError) {
    try storage.writeJSON(style, named: Self.roomStyleFileName)
  }

  public static let catFileName = "cat-choice.json"

  /// The saved cat, or the standard one when nothing readable is saved.
  public func loadCat() -> CatChoice {
    (try? storage.readJSON(CatChoice.self, named: Self.catFileName)) ?? .standard
  }

  public func saveCat(_ cat: CatChoice) throws(PersistenceError) {
    try storage.writeJSON(cat, named: Self.catFileName)
  }

  public static let homeVariantFileName = "home-variant.json"

  /// The saved layout of Home, or the standard one when nothing readable is saved.
  public func loadHomeVariant() -> HomeVariant {
    (try? storage.readJSON(HomeVariant.self, named: Self.homeVariantFileName)) ?? .standard
  }

  public func saveHomeVariant(_ variant: HomeVariant) throws(PersistenceError) {
    try storage.writeJSON(variant, named: Self.homeVariantFileName)
  }

  public static let lightingFileName = "room-lighting.json"

  /// The saved lighting of the rooms, or the standard one when nothing readable is saved.
  public func loadLighting() -> RoomLighting {
    (try? storage.readJSON(RoomLighting.self, named: Self.lightingFileName)) ?? .standard
  }

  public func saveLighting(_ lighting: RoomLighting) throws(PersistenceError) {
    try storage.writeJSON(lighting, named: Self.lightingFileName)
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
  /// How a scene with more than one room dresses it. Kept beside the flags, in its own file.
  public private(set) var roomStyle: RoomStyle
  /// Which cat the rooms show, and its coat. Kept beside the flags, in its own file.
  public private(set) var cat: CatChoice
  /// How Home is laid out around the room. Kept beside the flags, in its own file.
  public private(set) var homeVariant: HomeVariant
  /// The hour Home pretends it is, so the light of any hour can be tried. `nil` follows the clock.
  public private(set) var pretendHour: Int?
  /// How the rooms are lit. Kept beside the flags, in its own file.
  public private(set) var lighting: RoomLighting

  @ObservationIgnored private let store: WidgetFeaturesStore?
  @ObservationIgnored private let onChange: @MainActor () -> Void

  public init(store: WidgetFeaturesStore?, onChange: @escaping @MainActor () -> Void = {}) {
    self.store = store
    self.onChange = onChange
    features = store?.load() ?? WidgetFeatures()
    roomStyle = store?.loadRoomStyle() ?? .standard
    cat = store?.loadCat() ?? .standard
    homeVariant = store?.loadHomeVariant() ?? .standard
    pretendHour = store?.loadPretendHour()
    lighting = store?.loadLighting() ?? .standard
  }

  public func setLighting(_ lighting: RoomLighting) {
    guard self.lighting != lighting else { return }
    self.lighting = lighting
    try? store?.saveLighting(lighting)
  }

  public func setPretendHour(_ hour: Int?) {
    let hour = hour.flatMap { (0..<24).contains($0) ? $0 : nil }
    guard pretendHour != hour else { return }
    pretendHour = hour
    try? store?.savePretendHour(hour)
  }

  public func setHomeVariant(_ variant: HomeVariant) {
    guard homeVariant != variant else { return }
    homeVariant = variant
    try? store?.saveHomeVariant(variant)
  }

  public func setRoomStyle(_ style: RoomStyle) {
    guard roomStyle != style else { return }
    roomStyle = style
    try? store?.saveRoomStyle(style)
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
