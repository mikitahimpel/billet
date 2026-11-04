/// One choice of a `Single` or `Multi` onboarding step.
public struct OnboardingOption: Codable, Hashable, Sendable {
  public let id: OnboardingOptionId
  public let label: LocalizedText
  public let emoji: String?
  /// Picking it clears the other picks of a `Multi` step, as "Just exploring" does.
  public let exclusive: Bool?

  public init(
    id: OnboardingOptionId, label: LocalizedText, emoji: String? = nil, exclusive: Bool? = nil
  ) {
    self.id = id
    self.label = label
    self.emoji = emoji
    self.exclusive = exclusive
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case label
    case emoji
    case exclusive
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(OnboardingOptionId.self, forKey: .id)
    label = try container.decode(LocalizedText.self, forKey: .label)
    emoji = try container.decodeOptionalKey(String.self, forKey: .emoji)
    exclusive = try container.decodeOptionalKey(Bool.self, forKey: .exclusive)
  }
}
