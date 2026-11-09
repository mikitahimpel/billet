import Foundation

/// Which cat lives in the room. The raw value is what gets stored, so it stays stable. A stored
/// value that is no longer a case (a removed cat) decodes as the standard choice.
public enum CatModel: String, CaseIterable, Codable, Hashable, Sendable {
  /// The standard cat, first so the picker lists it at the top.
  case marmalade
  case gingerChonk
  /// Made from an illustration, used with its author's permission.
  case illustratedTabby
  case detailed
  case detailedKitten
  case detailedFluffy
  case hero
  case idolGinger
  /// Where splats can't be drawn (before iOS 27, or on an older GPU) it is the Idol ginger mesh.
  case splatGinger
  case mooCat
  case fluffyWhite
  case britishGrey
  case greyTabby
  case tuxedoTom
  case tortie
  case bengal
  case calico
  case ragdoll
  case maineCoon
  case voidCat
  case siamese
  case idolCalico
  case idolGreyTabby

  public var title: String {
    switch self {
    case .detailed: "Detailed"
    case .detailedKitten: "Detailed kitten"
    case .detailedFluffy: "Detailed fluffy"
    case .hero: "Hero"
    case .idolGinger: "Idol ginger"
    case .splatGinger: "Splat ginger"
    case .marmalade: "Marmalade"
    case .mooCat: "Moo"
    case .fluffyWhite: "Fluffy white"
    case .britishGrey: "British grey"
    case .greyTabby: "Grey tabby"
    case .tuxedoTom: "Tuxedo"
    case .tortie: "Tortie"
    case .bengal: "Bengal"
    case .calico: "Calico"
    case .ragdoll: "Ragdoll"
    case .maineCoon: "Maine Coon"
    case .voidCat: "Void"
    case .siamese: "Siamese"
    case .gingerChonk: "Ginger chonk"
    case .illustratedTabby: "Illustrated tabby"
    case .idolCalico: "Idol calico"
    case .idolGreyTabby: "Idol grey tabby"
    }
  }

  public var detail: String {
    switch self {
    case .detailed: "The tabby up close: fur, eyelids, whiskers."
    case .detailedKitten: "Big head, big blue eyes, stubby legs."
    case .detailedFluffy: "Long-haired, with a mane and a plume tail."
    case .hero: "Chunky and plush, big glossy eyes, 26 clips."
    case .idolGinger: "Made by Idol from a picture of the tabby."
    case .splatGinger: "Idol's ginger as a soft Gaussian splat."
    case .marmalade: "A soft ginger tabby who keeps the window seat warm."
    case .mooCat: "Black and white like a cow, and a bit of a clown."
    case .fluffyWhite: "Long white fur, kept spotless."
    case .britishGrey: "A blue British shorthair, slow and serene."
    case .greyTabby: "A grey tabby with an eye on every corner."
    case .tuxedoTom: "Black and white, poised and a little aloof."
    case .tortie: "Tortoiseshell, with opinions."
    case .bengal: "Spotted and quick, always ready to pounce."
    case .calico: "A calico who comes over for a cuddle."
    case .ragdoll: "Floppy, gentle and in no hurry."
    case .maineCoon: "A big, gentle long-hair."
    case .voidCat: "A black cat with amber eyes, curious about everything."
    case .siamese: "Blue eyes, dark points, always has something to say."
    case .gingerChonk: "A round ginger tabby who would rather loaf than walk."
    case .illustratedTabby: "A grey tabby made by Idol from an illustration."
    case .idolCalico: "Made by Idol from a picture of a calico."
    case .idolGreyTabby: "Made by Idol from a picture of the grey tabby."
    }
  }

  /// Whether the cat picker offers it. Every cat is offered: one whose sleep would sink its head
  /// into its body (the grey tabby) dozes in its loaf instead, set in its clip table.
  public var isListed: Bool {
    switch self {
    case .gingerChonk, .illustratedTabby, .detailed, .detailedKitten, .detailedFluffy, .hero,
      .idolGinger,
      .marmalade,
      .mooCat, .fluffyWhite, .britishGrey, .greyTabby, .tuxedoTom, .tortie, .bengal, .calico,
      .ragdoll, .maineCoon, .voidCat, .siamese, .splatGinger, .idolCalico, .idolGreyTabby:
      true
    }
  }

  /// The Gaussian-splat body this model wears where splats can be drawn, `<name>.bsplat` beside
  /// the cat files; elsewhere its mesh shows. Nil for a cat that is only a mesh.
  public var splatBody: String? {
    switch self {
    case .detailed, .detailedKitten, .detailedFluffy, .hero, .idolGinger, .marmalade, .mooCat,
      .fluffyWhite,
      .britishGrey, .greyTabby, .tuxedoTom, .tortie, .bengal, .calico, .ragdoll, .maineCoon,
      .voidCat,
      .siamese,
      .gingerChonk, .illustratedTabby,
      .idolCalico,
      .idolGreyTabby:
      nil
    case .splatGinger: "Splat_ginger"
    }
  }

  /// The model whose compiled mesh, clips and textures this one uses. A splat cat moves on the
  /// skeleton of the mesh made from the same Idol picture, and shows that mesh where splats can't
  /// be drawn.
  public var mesh: CatModel {
    switch self {
    case .splatGinger: .idolGinger
    case .detailed, .detailedKitten, .detailedFluffy, .hero, .idolGinger, .marmalade, .mooCat,
      .fluffyWhite,
      .britishGrey, .greyTabby, .tuxedoTom, .tortie, .bengal, .calico, .ragdoll, .maineCoon,
      .voidCat,
      .siamese,
      .gingerChonk, .illustratedTabby,
      .idolCalico,
      .idolGreyTabby:
      self
    }
  }

  /// Coats this model can wear: one painted texture per coat, `Cat_<model>_<coat>.jpg`.
  public var coats: [CatCoat] {
    switch self {
    case .detailed, .detailedKitten, .detailedFluffy, .hero: [.natural, .greyWhite, .black]
    // Idol bakes the coat it saw into the texture; another coat is another Idol cat.
    case .idolGinger, .marmalade, .mooCat, .fluffyWhite, .britishGrey, .greyTabby, .tuxedoTom,
      .tortie, .bengal,
      .calico, .ragdoll, .maineCoon, .voidCat, .siamese, .gingerChonk, .illustratedTabby,
      .idolCalico,
      .idolGreyTabby,
      .splatGinger:
      [.natural]
    }
  }
}

/// A cat's coat colour. `natural` is the one the model was made with.
public enum CatCoat: String, CaseIterable, Codable, Hashable, Sendable {
  case natural
  case greyWhite
  case black

  public var title: String {
    switch self {
    case .natural: "As made"
    case .greyWhite: "Grey and white"
    case .black: "Black"
    }
  }
}

public struct CatChoice: Codable, Hashable, Sendable {
  public var model: CatModel
  public var coat: CatCoat

  /// What a room shows before anyone chooses, and what a stored choice of a removed cat becomes.
  public static let standard = CatChoice(model: .marmalade, coat: .natural)

  public init(model: CatModel, coat: CatCoat = .natural) {
    self.model = model
    self.coat = model.coats.contains(coat) ? coat : .natural
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let model = (try? container.decode(CatModel.self, forKey: .model)) ?? Self.standard.model
    let coat = (try? container.decode(CatCoat.self, forKey: .coat)) ?? .natural
    self.init(model: model, coat: coat)
  }
}
