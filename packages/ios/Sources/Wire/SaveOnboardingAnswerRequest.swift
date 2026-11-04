/// `POST /v1/onboarding/answers`, answered with 204. The server keeps one answer per account and
/// step, the one with the later `answeredAt` (epoch milliseconds), so a queued retry is safe to
/// send again. A 400 means the step or option is gone: drop the answer. A 503 means retry.
///
/// Besides the served steps it takes the app's own: `cat_coat` (`single`, any coat id),
/// `cat_name` (`text`, at most 24 characters; skipped means Mochi) and `invite_partner`
/// (`single` with `sent`, or skipped).
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
