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
}

/// The flags the settings screen edits, widget features and lab experiments alike. Each change is
/// saved, then `onChange` lets the widgets redraw.
@MainActor
@Observable
public final class WidgetFeaturesModel {
  public private(set) var features: WidgetFeatures
  /// How a scene with more than one room dresses it. Kept beside the flags, in its own file.
  public private(set) var roomStyle: RoomStyle

  @ObservationIgnored private let store: WidgetFeaturesStore?
  @ObservationIgnored private let onChange: @MainActor () -> Void

  public init(store: WidgetFeaturesStore?, onChange: @escaping @MainActor () -> Void = {}) {
    self.store = store
    self.onChange = onChange
    features = store?.load() ?? WidgetFeatures()
    roomStyle = store?.loadRoomStyle() ?? .standard
  }

  public func setRoomStyle(_ style: RoomStyle) {
    guard roomStyle != style else { return }
    roomStyle = style
    try? store?.saveRoomStyle(style)
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
