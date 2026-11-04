import Foundation

/// What kind of animal a pet is. The clip vocabulary, cues, moments and needs serve every species;
/// a new one adds a case here, its models, and their anatomy.
public enum PetSpecies: String, CaseIterable, Codable, Hashable, Sendable {
  case cat
}

/// What a room needs to know about a pet's body to size it, find it under a finger and hang a note
/// or a toy from its mouth. Rooms read it from the model rather than assume one shape.
public struct PetAnatomy: Hashable, Sendable {
  /// The longest side across the floor, in the model's own metres. A room scales the pet by the
  /// length it wants over this.
  public var length: Float
  /// The head, for touch: forward of and above the feet, as fractions of the pet's length.
  public var head: SIMD2<Float>
  /// The tail, for touch: behind and above the feet, as fractions of the pet's length.
  public var tail: SIMD2<Float>
  /// From the head joint to the mouth, in the model's own metres: forward, then down.
  public var mouth: SIMD2<Float>

  public init(length: Float, head: SIMD2<Float>, tail: SIMD2<Float>, mouth: SIMD2<Float>) {
    self.length = length
    self.head = head
    self.tail = tail
    self.mouth = mouth
  }

  /// The cats made for billet on the shared skeleton, at the size they are built to.
  public static let madeCat = PetAnatomy(
    length: 0.2998, head: [0.36, 0.42], tail: [0.3, 0.28], mouth: [0.05, 0.02])
}

extension CatModel {
  public var species: PetSpecies { .cat }

  public var anatomy: PetAnatomy {
    switch self {
    case .hero:
      // Longer across the floor than the others, with a head 1.27 times the detailed cat's.
      PetAnatomy(length: 0.3192, head: [0.36, 0.44], tail: [0.3, 0.28], mouth: [0.064, 0.025])
    case .detailed, .detailedKitten, .detailedFluffy, .tabby, .plush, .chibi, .kitten, .tuxedo,
      .idolGinger, .gingerChonk, .idolIlya, .idolCalico, .idolGreyTabby, .splatGinger:
      .madeCat
    }
  }
}
