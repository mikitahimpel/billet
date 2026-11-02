import Foundation

/// Which cat lives in the room. The raw value is what gets stored, so it stays stable.
public enum CatModel: String, CaseIterable, Codable, Hashable, Sendable {
  /// Mochi, the curled grey tabby the rooms have always had.
  case mochi
  /// A ginger tabby with flat facets, to match the low-poly furniture.
  case tabby
  /// The same tabby with soft shading.
  case plush
  /// The same tabby sculpted in detail: painted fur, eyelids, whiskers, toes and toe beans.
  case detailed
  /// The detailed tabby as a kitten: a bigger head, big blue eyes, stubby legs, fluffier fur.
  case detailedKitten
  /// The detailed tabby long-haired: a mane, britches, a plume tail and lynx tips on the ears.
  case detailedFluffy
  /// A plush toy cat: a very big head on a small body.
  case chibi
  /// A fluffy kitten with tufted cheeks, chest and tail.
  case kitten
  /// A black cat with a white bib, muzzle and socks.
  case tuxedo
  /// "Cat" by Quaternius, CC0: a blocky toy cat.
  case blocky
  /// "Cat" by J-Toastie, CC BY 3.0: a slim low-poly cat.
  case slim

  public var title: String {
    switch self {
    case .mochi: "Mochi"
    case .tabby: "Tabby"
    case .plush: "Plush tabby"
    case .detailed: "Detailed"
    case .detailedKitten: "Detailed kitten"
    case .detailedFluffy: "Detailed fluffy"
    case .chibi: "Chibi"
    case .kitten: "Fluffy kitten"
    case .tuxedo: "Tuxedo"
    case .blocky: "Blocky"
    case .slim: "Slim"
    }
  }

  public var detail: String {
    switch self {
    case .mochi: "The curled grey tabby."
    case .tabby: "Ginger tabby, flat facets like the furniture."
    case .plush: "The tabby, soft-shaded."
    case .detailed: "The tabby up close: fur, eyelids, whiskers."
    case .detailedKitten: "Big head, big blue eyes, stubby legs."
    case .detailedFluffy: "Long-haired, with a mane and a plume tail."
    case .chibi: "Big head, tiny body, huge eyes."
    case .kitten: "Tufted cheeks and a fluffy tail."
    case .tuxedo: "Black with a white bib and socks."
    case .blocky: "A toy box cat. By Quaternius, CC0."
    case .slim: "A slim low-poly cat. By J-Toastie, CC BY 3.0."
    }
  }

  /// Whether each coat is a whole painted texture, `Cat_<model>_<coat>.jpg`, not a palette.
  public var paintsCoatTextures: Bool {
    switch self {
    case .detailed, .detailedKitten, .detailedFluffy: true
    case .mochi, .tabby, .plush, .chibi, .kitten, .tuxedo, .blocky, .slim: false
    }
  }

  /// Coats this model can wear. Models painted from a palette can swap it; the detailed cats have
  /// one painted texture per coat; the others keep theirs.
  public var coats: [CatCoat] {
    switch self {
    case .tabby, .plush, .chibi, .kitten, .tuxedo: CatCoat.allCases
    case .detailed, .detailedKitten, .detailedFluffy: [.natural, .greyWhite, .black]
    case .mochi, .blocky, .slim: [.natural]
    }
  }
}

/// A cat's coat colour. `natural` is the one the model was made with.
public enum CatCoat: String, CaseIterable, Codable, Hashable, Sendable {
  case natural
  case ginger
  case greyWhite
  case black
  case cream

  public var title: String {
    switch self {
    case .natural: "As made"
    case .ginger: "Ginger"
    case .greyWhite: "Grey and white"
    case .black: "Black"
    case .cream: "Cream"
    }
  }
}

/// The cat a room shows: a model and the coat it wears.
public struct CatChoice: Codable, Hashable, Sendable {
  public var model: CatModel
  public var coat: CatCoat

  /// What a room shows before anyone chooses.
  public static let standard = CatChoice(model: .mochi, coat: .natural)

  public init(model: CatModel, coat: CatCoat = .natural) {
    self.model = model
    self.coat = model.coats.contains(coat) ? coat : .natural
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let model = (try? container.decode(CatModel.self, forKey: .model)) ?? .mochi
    let coat = (try? container.decode(CatCoat.self, forKey: .coat)) ?? .natural
    self.init(model: model, coat: coat)
  }
}
