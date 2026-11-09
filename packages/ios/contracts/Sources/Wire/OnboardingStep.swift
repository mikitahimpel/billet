/// A skip is sent as ``OnboardingAnswer/skipped``.
public enum OnboardingStep: Codable, Hashable, Sendable {
  /// An age is one of these, over buckets.
  case single(OnboardingChoiceStep)
  /// An `exclusive` option goes alone.
  case multi(OnboardingChoiceStep)
  case range(OnboardingRangeStep)
  case text(OnboardingTextStep)

  public var id: OnboardingStepId {
    switch self {
    case .single(let step), .multi(let step): step.id
    case .range(let step): step.id
    case .text(let step): step.id
    }
  }

  private enum TagKey: String, CodingKey {
    case tag = "_tag"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: TagKey.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Single": self = .single(try OnboardingChoiceStep(from: decoder))
    case "Multi": self = .multi(try OnboardingChoiceStep(from: decoder))
    case "Range": self = .range(try OnboardingRangeStep(from: decoder))
    case "Text": self = .text(try OnboardingTextStep(from: decoder))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: TagKey.self)
    switch self {
    case .single(let step):
      try container.encode("Single", forKey: .tag)
      try step.encode(to: encoder)
    case .multi(let step):
      try container.encode("Multi", forKey: .tag)
      try step.encode(to: encoder)
    case .range(let step):
      try container.encode("Range", forKey: .tag)
      try step.encode(to: encoder)
    case .text(let step):
      try container.encode("Text", forKey: .tag)
      try step.encode(to: encoder)
    }
  }
}

public struct OnboardingChoiceStep: Codable, Hashable, Sendable {
  public let id: OnboardingStepId
  public let title: LocalizedText
  public let subtitle: LocalizedText?
  public let skippable: Bool
  public let options: [OnboardingOption]

  public init(
    id: OnboardingStepId, title: LocalizedText, subtitle: LocalizedText? = nil,
    skippable: Bool = true, options: [OnboardingOption]
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.skippable = skippable
    self.options = options
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case subtitle
    case skippable
    case options
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(OnboardingStepId.self, forKey: .id)
    title = try container.decode(LocalizedText.self, forKey: .title)
    subtitle = try container.decodeOptionalKey(LocalizedText.self, forKey: .subtitle)
    skippable = try container.decode(Bool.self, forKey: .skippable)
    options = try container.decode([OnboardingOption].self, forKey: .options)
    guard !options.isEmpty else {
      throw DecodingError.dataCorruptedError(
        forKey: .options, in: container, debugDescription: "a choice step needs an option")
    }
  }
}

public struct OnboardingRangeStep: Codable, Hashable, Sendable {
  public let id: OnboardingStepId
  public let title: LocalizedText
  public let subtitle: LocalizedText?
  public let skippable: Bool
  public let min: Int
  public let max: Int
  public let step: Int
  public let unit: LocalizedText?

  public init(
    id: OnboardingStepId, title: LocalizedText, subtitle: LocalizedText? = nil,
    skippable: Bool = true, min: Int, max: Int, step: Int = 1, unit: LocalizedText? = nil
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.skippable = skippable
    self.min = min
    self.max = max
    self.step = step
    self.unit = unit
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case subtitle
    case skippable
    case min
    case max
    case step
    case unit
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(OnboardingStepId.self, forKey: .id)
    title = try container.decode(LocalizedText.self, forKey: .title)
    subtitle = try container.decodeOptionalKey(LocalizedText.self, forKey: .subtitle)
    skippable = try container.decode(Bool.self, forKey: .skippable)
    min = try container.decode(Int.self, forKey: .min)
    max = try container.decode(Int.self, forKey: .max)
    step = try container.decode(Int.self, forKey: .step)
    unit = try container.decodeOptionalKey(LocalizedText.self, forKey: .unit)
    guard step >= 1 else {
      throw DecodingError.dataCorruptedError(
        forKey: .step, in: container, debugDescription: "step must be 1 or more")
    }
  }
}

public struct OnboardingTextStep: Codable, Hashable, Sendable {
  public let id: OnboardingStepId
  public let title: LocalizedText
  public let subtitle: LocalizedText?
  public let skippable: Bool
  public let placeholder: LocalizedText?
  /// Counted as Swift's `String.count`.
  public let maxLength: Int

  public init(
    id: OnboardingStepId, title: LocalizedText, subtitle: LocalizedText? = nil,
    skippable: Bool = true, placeholder: LocalizedText? = nil, maxLength: Int
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.skippable = skippable
    self.placeholder = placeholder
    self.maxLength = maxLength
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case subtitle
    case skippable
    case placeholder
    case maxLength
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(OnboardingStepId.self, forKey: .id)
    title = try container.decode(LocalizedText.self, forKey: .title)
    subtitle = try container.decodeOptionalKey(LocalizedText.self, forKey: .subtitle)
    skippable = try container.decode(Bool.self, forKey: .skippable)
    placeholder = try container.decodeOptionalKey(LocalizedText.self, forKey: .placeholder)
    maxLength = try container.decode(Int.self, forKey: .maxLength)
    guard maxLength >= 1 else {
      throw DecodingError.dataCorruptedError(
        forKey: .maxLength, in: container, debugDescription: "maxLength must be 1 or more")
    }
  }
}
