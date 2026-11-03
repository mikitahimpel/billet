import Foundation
import Pet

/// A test the server can run on pairs, and the variants this build contains. Assignment only
/// chooses between variants listed here: a variant the server names that is not listed is ignored,
/// so the server can never turn on something App Review has not seen in this build.
///
/// Add one here only with the screens for every variant, complete and reviewable.
/// `docs/experiments.md` has the steps.
public struct Experiment: Hashable, Sendable {
  public let key: String
  public let variants: Set<String>

  public init(key: String, variants: Set<String>) {
    self.key = key
    self.variants = variants
  }

  /// A Labs setting the server can set too: one variant per case, named as `remoteVariant` says.
  public init<Choice: RemoteChoice>(key: String, choices: Choice.Type) {
    self.init(key: key, variants: Set(Choice.allCases.map(\.remoteVariant)))
  }
}

/// A Labs setting whose cases are the variants of a remote flag. A variant id is the case's raw
/// value in kebab-case (`amberLantern` is `amber-lantern`), as the server's registry names it.
public protocol RemoteChoice: CaseIterable, RawRepresentable<String> {}

extension RemoteChoice {
  /// The id the server uses for this case.
  public var remoteVariant: String {
    rawValue.reduce(into: "") { id, character in
      if character.isUppercase { id += "-" }
      id += character.lowercased()
    }
  }

  /// The case a variant id names, or `nil` for a variant this build does not have.
  public init?(remoteVariant variant: String) {
    guard let match = Self.allCases.first(where: { $0.remoteVariant == variant }) else {
      return nil
    }
    self = match
  }
}

extension RoomLighting: RemoteChoice {}
extension WindowView: RemoteChoice {}
extension HomeVariant: RemoteChoice {}
extension Shopkeeper: RemoteChoice {}

public enum Experiments {
  /// Which room Home shows: a night bedroom with a sunset lamp, or a daybed under a window.
  public static let homeDirection = Experiment(
    key: "home-direction", variants: ["window-seat", "sunset-lamp"])

  /// How the rooms are lit (Labs > Lighting).
  public static let roomLighting = Experiment(key: "room-lighting", choices: RoomLighting.self)

  /// What the room's window looks out on (Labs > View). Only the view: no weather or hour.
  public static let windowView = Experiment(key: "window-view", choices: WindowView.self)

  /// How Home is laid out around the room (Labs > Home).
  public static let homeLayout = Experiment(key: "home-layout", choices: HomeVariant.self)

  /// Who keeps the 3D shop (Labs > Shopkeeper).
  public static let shopkeeper = Experiment(key: "shopkeeper", choices: Shopkeeper.self)

  public static let all: [Experiment] = [
    homeDirection, roomLighting, windowView, homeLayout, shopkeeper,
  ]
}

extension RoomStyle {
  /// The room style a `home-direction` variant stands for, or `nil` for a variant this build does
  /// not have.
  public init?(homeDirectionVariant variant: String) {
    switch variant {
    case "window-seat": self = .windowSeat
    case "sunset-lamp": self = .sunsetLamp
    default: return nil
    }
  }
}

/// The variants the server last gave this pair, kept for the next launch and for offline.
///
/// Each answer from the server replaces the whole set, never merges into it: an experiment the
/// server stops listing (switched off, or ended) disappears here too, and the app goes back to what
/// it did before the test.
public struct RemoteFlags: Codable, Equatable, Sendable {
  /// The most experiments kept. The server runs a handful; this stops a bad answer filling storage.
  public static let limit = 50

  private var assigned: [String: String]

  public init(assignments: [String: String] = [:]) {
    assigned = Dictionary(
      uniqueKeysWithValues: assignments.sorted { $0.key < $1.key }.prefix(Self.limit).map { $0 })
  }

  public var isEmpty: Bool { assigned.isEmpty }

  /// The variant for `experiment` if the server gave one and this build has it.
  public func variant(of experiment: Experiment) -> String? {
    assigned[experiment.key].flatMap { experiment.variants.contains($0) ? $0 : nil }
  }

  /// The case the server gave for `experiment`, if it gave one and this build has it.
  public func choice<Choice: RemoteChoice>(
    of experiment: Experiment, as _: Choice.Type = Choice.self
  ) -> Choice? {
    variant(of: experiment).flatMap(Choice.init(remoteVariant:))
  }

  public init(from decoder: any Decoder) throws {
    let all = try decoder.singleValueContainer().decode([String: String].self)
    self.init(assignments: all)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(assigned)
  }
}
