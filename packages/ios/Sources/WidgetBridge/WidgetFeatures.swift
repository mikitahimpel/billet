import Foundation
import Observation
import Persistence

/// Which widget features are on. Anything never switched follows its default, so a feature added
/// later does not silently turn off for someone who already has stored choices.
public struct WidgetFeatures: Equatable, Sendable {
  private var choices: [WidgetFeature: Bool]

  public init(choices: [WidgetFeature: Bool] = [:]) {
    self.choices = choices
  }

  public func isOn(_ feature: WidgetFeature) -> Bool {
    choices[feature] ?? feature.defaultOn
  }

  public mutating func set(_ feature: WidgetFeature, on: Bool) {
    choices[feature] = on
  }

  /// The features that are on, in declaration order.
  public var enabled: [WidgetFeature] {
    WidgetFeature.allCases.filter(isOn)
  }
}

extension WidgetFeatures: Codable {
  public init(from decoder: any Decoder) throws {
    let stored = try decoder.singleValueContainer().decode([String: Bool].self)
    var choices: [WidgetFeature: Bool] = [:]
    for (key, value) in stored {
      if let feature = WidgetFeature(rawValue: key) { choices[feature] = value }
    }
    self.choices = choices
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(
      Dictionary(uniqueKeysWithValues: choices.map { ($0.key.rawValue, $0.value) }))
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
}

/// The flags the settings screen edits. Each change is saved, then `onChange` lets the widgets
/// redraw.
@MainActor
@Observable
public final class WidgetFeaturesModel {
  public private(set) var features: WidgetFeatures

  @ObservationIgnored private let store: WidgetFeaturesStore?
  @ObservationIgnored private let onChange: @MainActor () -> Void

  public init(store: WidgetFeaturesStore?, onChange: @escaping @MainActor () -> Void = {}) {
    self.store = store
    self.onChange = onChange
    features = store?.load() ?? WidgetFeatures()
  }

  public func isOn(_ feature: WidgetFeature) -> Bool {
    features.isOn(feature)
  }

  public func set(_ feature: WidgetFeature, on: Bool) {
    guard features.isOn(feature) != on else { return }
    features.set(feature, on: on)
    try? store?.save(features)
    onChange()
  }
}
