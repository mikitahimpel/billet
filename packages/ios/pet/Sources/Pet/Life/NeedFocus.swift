import Foundation

/// Which need, if any, the pet acts on now. A need is low below ``LifeConfig/lowBelow`` until it is
/// back above ``LifeConfig/lowUntil``, so a value at the line never flickers. One low need is drawn
/// by softmax over urgency `(1 − n)²` and kept while low; deterministic for a given seed.
public struct NeedFocus: Sendable {
  public private(set) var low: Set<PetNeed> = []
  public private(set) var focus: PetNeed?
  private var random: SplitMix64
  private let config: LifeConfig

  public init(config: LifeConfig = .standard, seed: UInt64 = 1) {
    self.config = config
    random = SplitMix64(seed: seed)
  }

  @discardableResult
  public mutating func update(_ needs: PetNeeds) -> PetNeed? {
    for need in PetNeed.allCases {
      if low.contains(need) {
        if needs[need] > config.lowUntil { low.remove(need) }
      } else if needs[need] < config.lowBelow {
        low.insert(need)
      }
    }
    if let focus, low.contains(focus) { return focus }
    let open = PetNeed.allCases.filter(low.contains)
    focus = pick(among: open, values: needs)
    return focus
  }

  public static func urgency(_ value: Double) -> Double {
    let gap = 1 - value
    return gap * gap
  }

  /// The softmax `e^(uᵢ/T) / Σ e^(uⱼ/T)` over `needs`, in their order.
  public static func probabilities(
    _ needs: [PetNeed], values: PetNeeds, temperature: Double
  ) -> [Double] {
    let urgencies = needs.map { urgency(values[$0]) }
    guard let top = urgencies.max() else { return [] }
    let t = max(temperature, 1e-6)
    let weights = urgencies.map { exp(($0 - top) / t) }
    let total = weights.reduce(0, +)
    return weights.map { $0 / total }
  }

  private mutating func pick(among needs: [PetNeed], values: PetNeeds) -> PetNeed? {
    guard !needs.isEmpty else { return nil }
    let odds = Self.probabilities(needs, values: values, temperature: config.temperature)
    var roll = random.next(in: 0...1)
    for (need, p) in zip(needs, odds) {
      roll -= p
      if roll <= 0 { return need }
    }
    return needs.last
  }
}

/// What the room's behaviour takes from the pet's life.
public struct LifeDrive: Hashable, Sendable {
  public var asleep: Bool
  public var focus: PetNeed?

  public init(asleep: Bool = false, focus: PetNeed? = nil) {
    self.asleep = asleep
    self.focus = focus
  }
}
