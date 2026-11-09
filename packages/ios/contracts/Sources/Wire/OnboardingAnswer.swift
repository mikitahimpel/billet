/// A skip is an answer too.
public enum OnboardingAnswer: Codable, Hashable, Sendable {
  case skipped
  case single(option: OnboardingOptionId)
  case multi(options: [OnboardingOptionId])
  case range(value: Int)
  case text(String)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case option
    case options
    case value
    case text
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Skipped": self = .skipped
    case "Single":
      self = .single(option: try container.decode(OnboardingOptionId.self, forKey: .option))
    case "Multi":
      let options = try container.decode([OnboardingOptionId].self, forKey: .options)
      guard !options.isEmpty, Set(options).count == options.count else {
        throw DecodingError.dataCorruptedError(
          forKey: .options, in: container,
          debugDescription: "options must be distinct, at least one")
      }
      self = .multi(options: options)
    case "Range": self = .range(value: try container.decode(Int.self, forKey: .value))
    case "Text":
      let text = try container.decode(String.self, forKey: .text)
      guard !text.allSatisfy(\.isWhitespace) else {
        throw DecodingError.dataCorruptedError(
          forKey: .text, in: container, debugDescription: "text must not be blank")
      }
      self = .text(text)
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .skipped:
      try container.encode("Skipped", forKey: .tag)
    case .single(let option):
      try container.encode("Single", forKey: .tag)
      try container.encode(option, forKey: .option)
    case .multi(let options):
      try container.encode("Multi", forKey: .tag)
      try container.encode(options, forKey: .options)
    case .range(let value):
      try container.encode("Range", forKey: .tag)
      try container.encode(value, forKey: .value)
    case .text(let text):
      try container.encode("Text", forKey: .tag)
      try container.encode(text, forKey: .text)
    }
  }
}
