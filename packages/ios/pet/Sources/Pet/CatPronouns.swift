import Foundation

/// How the pair words the cat. They choose it; until then it is `they`, which misgenders no one.
public enum CatPronouns: String, CaseIterable, Codable, Sendable {
  case she
  case he
  case they

  public static let unchosen = CatPronouns.they

  /// The picker's label: "She / her".
  public var label: String {
    switch self {
    case .she: String(localized: "She / her")
    case .he: String(localized: "He / him")
    case .they: String(localized: "They / them")
    }
  }

  /// Every phrase about the cat goes through here, so no screen picks a pronoun itself.
  public func say(_ phrase: CatPhrase) -> String {
    let forms = phrase.forms
    return switch self {
    case .she: forms.she
    case .he: forms.he
    case .they: forms.they
    }
  }
}

/// A line of copy that has to name the cat as "she", "he" or "they". Each case holds all three
/// wordings whole, because the verb moves with the pronoun ("she is", "they are") and a template with
/// a hole for the pronoun would get it wrong.
public enum CatPhrase: Sendable, Hashable {
  case napsOnOwn
  case tapToPet
  case ringExplained
  case portraitTreats(price: Int)
  case needsSettlingIn(name: String)
  case dayStarting
  case aboutHeading
  case opensNeeds
  case doubleTapToPet
  case bowlCapped
  case tooMuchWarning
  case tooMuchResult
  case widgetBlurb
  case widgetShowcaseState
  case widgetShowcaseMood
  case brainFooter(name: String)
  case brushGoal
  case bedSpot
  case boxSpot

  var forms: Forms {
    switch self {
    case .napsOnOwn:
      Forms(she: "Naps on her own", he: "Naps on his own", they: "Naps on their own")
    case .tapToPet:
      Forms(
        she: "Tap her in the room to pet her.", he: "Tap him in the room to pet him.",
        they: "Tap them in the room to pet them.")
    case .ringExplained:
      Forms(
        she: "The ring shows how full, rested, playful and loved she is. "
          + "Tap her portrait to care for her.",
        he: "The ring shows how full, rested, playful and loved he is. "
          + "Tap his portrait to care for him.",
        they: "The ring shows how full, rested, playful and loved they are. "
          + "Tap their portrait to care for them.")
    case .portraitTreats(let price):
      Forms(
        she: "Her portrait opens her treats: one fills her up more than a pet, for \(price) coins.",
        he: "His portrait opens his treats: one fills him up more than a pet, for \(price) coins.",
        they: "Their portrait opens their treats: one fills them up more than a pet, "
          + "for \(price) coins.")
    case .needsSettlingIn(let name):
      Forms(
        she: "\(name) is settling in. Her needs show here soon.",
        he: "\(name) is settling in. His needs show here soon.",
        they: "\(name) is settling in. Their needs show here soon.")
    case .dayStarting:
      Forms(
        she: "Her day is only starting. What she gets up to shows here.",
        he: "His day is only starting. What he gets up to shows here.",
        they: "Their day is only starting. What they get up to shows here.")
    case .aboutHeading:
      Forms(she: "About her", he: "About him", they: "About them")
    case .opensNeeds:
      Forms(
        she: "Opens her needs and care", he: "Opens his needs and care",
        they: "Opens their needs and care")
    case .doubleTapToPet:
      Forms(
        she: "Double tap to pet her.", he: "Double tap to pet him.", they: "Double tap to pet them."
      )
    case .bowlCapped:
      Forms(
        she: "The bowl is full: she'll be stuffed", he: "The bowl is full: he'll be stuffed",
        they: "The bowl is full: they'll be stuffed")
    case .tooMuchWarning:
      Forms(
        she: "Too much! She'll be stuffed", he: "Too much! He'll be stuffed",
        they: "Too much! They'll be stuffed")
    case .tooMuchResult:
      Forms(
        she: "Too much! She's stuffed", he: "Too much! He's stuffed",
        they: "Too much! They're stuffed")
    case .widgetBlurb:
      Forms(
        she: "Your cat, how she is right now, and a pet button.",
        he: "Your cat, how he is right now, and a pet button.",
        they: "Your cat, how they are right now, and a pet button.")
    case .widgetShowcaseState:
      Forms(
        she: "How she is right now, asleep, waiting or purring, "
          + "with a pet button and a hug for your partner.",
        he: "How he is right now, asleep, waiting or purring, "
          + "with a pet button and a hug for your partner.",
        they: "How they are right now, asleep, waiting or purring, "
          + "with a pet button and a hug for your partner.")
    case .widgetShowcaseMood:
      Forms(
        she: "A glyph for her mood.", he: "A glyph for his mood.", they: "A glyph for their mood.")
    case .brainFooter(let name):
      Forms(
        she: "With the brain off, \(name) lives on her own original timers. "
          + "The card shows what the brain has her doing and why: "
          + "her state, needs and the last thing she heard.",
        he: "With the brain off, \(name) lives on his own original timers. "
          + "The card shows what the brain has him doing and why: "
          + "his state, needs and the last thing he heard.",
        they: "With the brain off, \(name) lives on their own original timers. "
          + "The card shows what the brain has them doing and why: "
          + "their state, needs and the last thing they heard.")
    case .brushGoal:
      Forms(
        she: "Stroke her back, head to tail", he: "Stroke his back, head to tail",
        they: "Stroke their back, head to tail")
    case .bedSpot:
      Forms(she: "Her bed", he: "His bed", they: "Their bed")
    case .boxSpot:
      Forms(she: "Her box", he: "His box", they: "Their box")
    }
  }

  struct Forms {
    let she: String
    let he: String
    let they: String
  }
}
