import Foundation

/// How a cat model moves, on top of the temperament its pet was born with: a heavy cat is slower
/// than a lithe one whatever its nature, and each look has a couple of moves of its own that it
/// makes when it is settled.
public struct CatMotion: Hashable, Sendable {
  /// Against the temperament's own tempo: how fast its clips play and it gets about.
  public var tempo: Double
  /// Moves it makes now and then while it sits or loafs, its own fidgets.
  public var signature: [CatAction]
  /// The nature its look suggests. Its tempo and its moves are chosen to fit this temperament.
  public var temperament: CatTemperament?
  /// Seconds between its own moves while it is settled.
  public var every: Double

  public init(
    tempo: Double = 1, signature: [CatAction] = [], temperament: CatTemperament? = nil,
    every: Double = 11
  ) {
    self.tempo = tempo
    self.signature = signature
    self.temperament = temperament
    self.every = every
  }

  /// A cat with no moves of its own, at its temperament's tempo.
  public static let even = CatMotion()
}

extension CatModel {
  public var motion: CatMotion {
    switch self {
    case .detailed, .detailedKitten, .detailedFluffy, .hero, .idolGinger, .splatGinger,
      .idolCalico, .idolGreyTabby:
      .even
    case .gingerChonk:
      CatMotion(tempo: 0.85, signature: [.yawn, .slowBlink], temperament: .sleepyhead)
    case .idolIlya: CatMotion(tempo: 1, signature: [.happy, .headTilt], temperament: .cuddler)
    }
  }
}
