import FeatureOnboarding
import FeaturePairing
import Testing

struct OnboardingAppTests {
    @Test func theBundledQuestionsDecode() {
        let bundled = BundledOnboarding.load(from: .main)
        #expect(bundled.steps.count >= 1)
    }

    @Test func cancellingClearsTheFailure() {
        let wrong = PairingMachine.State.choosing(failure: .invalidCode, request: 3)
        let (next, outputs) = PairingMachine.transition(wrong, .cancelled)
        #expect(next == .choosing(failure: nil, request: 3))
        #expect(outputs.isEmpty)
    }
}
