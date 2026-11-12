import Foundation

/// The cat as her own sheet tells her: what kind of cat she is, where she likes to be and what
/// she has been up to today. It changes a few times an hour at most.
public struct CatAbout: Hashable, Sendable {
  public var asleep: Bool
  public var temperament: CatTemperament
  public var personality: CatPersonality
  public var favourite: RoomAffordance.Kind?
  /// Today's moments, oldest first.
  public var day: [CatDayMoment]

  public init(
    asleep: Bool = false, temperament: CatTemperament, personality: CatPersonality,
    favourite: RoomAffordance.Kind? = nil, day: [CatDayMoment] = []
  ) {
    self.asleep = asleep
    self.temperament = temperament
    self.personality = personality
    self.favourite = favourite
    self.day = day
  }
}

extension CatBrain {
  /// A cat adopted without a type is told as the one her traits lean to. Traits are rounded to
  /// twentieths, so a day's small drift redraws nothing.
  public func about(events: some Sequence<LifeEvent>) -> CatAbout {
    var traits = personality
    for trait in CatPersonality.Trait.allCases {
      traits[trait] = (traits[trait] * 20).rounded() / 20
    }
    let spot = memory.favourite.flatMap { $0.spotName(for: .they) == nil ? nil : $0 }
    return CatAbout(
      asleep: asleep, temperament: temperament ?? .fitting(nature), personality: traits,
      favourite: spot, day: dayMoments(events: events))
  }
}
