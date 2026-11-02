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
}

public enum Experiments {
  /// Which room Home shows: a night bedroom with a sunset lamp, or a daybed under a window.
  public static let homeDirection = Experiment(
    key: "home-direction", variants: ["window-seat", "sunset-lamp"])

  public static let all: [Experiment] = [homeDirection]
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

  public init(from decoder: any Decoder) throws {
    let all = try decoder.singleValueContainer().decode([String: String].self)
    self.init(assignments: all)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(assigned)
  }
}
