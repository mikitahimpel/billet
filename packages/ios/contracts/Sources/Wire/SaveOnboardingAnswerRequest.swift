/// Answered with 204. The server keeps the later `answeredAt` per account and step, so a retry is
/// safe. 400: the step or option is gone, drop it; 503: retry. Also takes `cat_coat`, `cat_name`
/// (at most 24 characters; skipped means Mochi) and `invite_partner` (`sent`, or skipped).
public struct SaveOnboardingAnswerRequest: Codable, Hashable, Sendable {
  public let version: String
  public let stepId: OnboardingStepId
  public let answer: OnboardingAnswer
  public let answeredAt: Int

  public init(
    version: String, stepId: OnboardingStepId, answer: OnboardingAnswer, answeredAt: Int
  ) {
    self.version = version
    self.stepId = stepId
    self.answer = answer
    self.answeredAt = answeredAt
  }
}
