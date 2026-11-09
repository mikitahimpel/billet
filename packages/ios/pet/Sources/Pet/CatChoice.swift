import Foundation

/// Which cat lives in the room. The raw value is what gets stored, so it stays stable. A stored
/// value that is no longer a case (a removed cat) decodes as the standard choice.
public enum CatModel: String, CaseIterable, Codable, Hashable, Sendable {
  /// A soft-matte ginger tabby, the room's own cat, by Idol from a FLUX.2-klein picture of the
  /// c1B concept. The standard cat, first so the picker lists it at the top.
  case marmalade
  /// A round ginger tabby in the room's style, by Idol from a FLUX.2-klein picture.
  case gingerChonk
  /// A grey tabby made by Idol from an illustration, used with its author's permission.
  case idolIlya
  /// A ginger tabby sculpted in detail: painted fur, eyelids, whiskers, toes and toe beans.
  case detailed
  /// The detailed tabby as a kitten: a bigger head, big blue eyes, stubby legs, fluffier fur.
  case detailedKitten
  /// The detailed tabby long-haired: a mane, britches, a plume tail and lynx tips on the ears.
  case detailedFluffy
  /// The hero: a stylised, chunky ginger tabby with a big round head, big glossy eyes and plush
  /// fur, made to read at room size and to move well. In Labs until it wins a side-by-side.
  case hero
  /// The detailed ginger tabby remade by Idol from one picture of it: a softer, plush-like body with
  /// the coat baked into one texture, on the shared skeleton with every clip.
  case idolGinger
  /// Idol's ginger tabby as the Gaussian splat Idol made, skinned to the shared skeleton. Where
  /// splats can't be drawn (before iOS 27, or on an older GPU) it is the Idol ginger mesh.
  case splatGinger
  /// A black-and-white cow-patched cat in the room's style, by Idol from a FLUX.2-klein picture.
  case mooCat
  /// A long-haired white cat in the room's style, by Idol from a FLUX.2-klein picture.
  case fluffyWhite
  /// A blue British shorthair in the room's style, by Idol from a FLUX.2-klein picture.
  case britishGrey
  /// A grey tabby in the room's style, by Idol from a FLUX.2-klein picture.
  case greyTabby
  /// A black-and-white tuxedo in the room's style, by Idol from a FLUX.2-klein picture.
  case tuxedoTom
  /// A tortoiseshell in the room's style, by Idol from a FLUX.2-klein picture.
  case tortie
  /// A Bengal in the room's style, by Idol from a FLUX.2-klein picture.
  case bengal
  /// A calico in the room's style, by Idol from a FLUX.2-klein picture.
  case calico
  /// A ragdoll in the room's style, by Idol from a FLUX.2-klein picture.
  case ragdoll
  /// A Maine Coon in the room's style, by Idol from a FLUX.2-klein picture.
  case maineCoon
  /// A black cat in the room's style, by Idol from a FLUX.2-klein picture.
  case voidCat
  /// A Siamese in the room's style, by Idol from a FLUX.2-klein picture.
  case siamese
  /// The detailed tabby painted calico, remade by Idol: plush body, baked coat, every clip.
  case idolCalico
  /// The detailed tabby in its grey-and-white coat, remade by Idol: plush body, baked coat, every clip.
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
    case .idolIlya: "Illustrated tabby"
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
    case .idolIlya: "A grey tabby made by Idol from an illustration."
    case .idolCalico: "Made by Idol from a picture of a calico."
    case .idolGreyTabby: "Made by Idol from a picture of the grey tabby."
    }
  }

  /// Whether the cat picker offers it. Every cat is offered: one whose sleep would sink its head
  /// into its body (the grey tabby) dozes in its loaf instead, set in its clip table.
  public var isListed: Bool {
    switch self {
    case .gingerChonk, .idolIlya, .detailed, .detailedKitten, .detailedFluffy, .hero, .idolGinger,
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
      .gingerChonk, .idolIlya,
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
      .gingerChonk, .idolIlya,
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
      .calico, .ragdoll, .maineCoon, .voidCat, .siamese, .gingerChonk, .idolIlya,
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

/// The cat a room shows: a model and the coat it wears.
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
