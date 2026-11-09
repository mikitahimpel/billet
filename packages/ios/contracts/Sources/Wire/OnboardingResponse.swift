/// The app ships a copy for offline use and sends `version` back with each answer.
public struct OnboardingResponse: Codable, Hashable, Sendable {
  public let version: String
  public let steps: [OnboardingStep]

  public init(version: String, steps: [OnboardingStep]) {
    self.version = version
    self.steps = steps
  }
}
