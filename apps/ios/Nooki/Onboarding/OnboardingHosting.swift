import FeatureOnboarding
import FeaturePairing
import RoomInterface
import SwiftUI

/// The hero cat and the two backdrops live with the room's drawing, which stays in the app.
struct AppOnboardingScenery: OnboardingScenery {
    func heroBackdrop() -> AnyView { AnyView(HeroBackdrop()) }
    func warmBackdrop() -> AnyView { AnyView(WarmBackdrop()) }
    func heroStage(coat: CatCoat, time: TimeInterval, pokedAt: TimeInterval?, moving: Bool) -> AnyView {
        AnyView(CatHeroStage(coat: coat, time: time, pokedAt: pokedAt, moving: moving))
    }
}

extension PairingModel: OnboardingPairing {
    public var onboardingState: OnboardingPairingState {
        switch state {
        case .choosing(let failure, let request):
            .choosing(failure: failure.map(Self.onboarding), request: request)
        case .creating(let request): .creating(request: request)
        case .waiting(let code, let expiresAt, let request):
            .waiting(code: code, expiresAt: expiresAt, request: request)
        case .claiming(let request): .claiming(request: request)
        case .paired: .paired
        }
    }

    private static func onboarding(_ failure: PairingFailure) -> OnboardingPairingFailure {
        OnboardingPairingFailure(isInvalidCode: failure == .invalidCode, message: PairingCopy.message(for: failure))
    }

    public func spaced(_ code: String) -> String { PairingCopy.spaced(code) }

    public func expiry(expiresAt: Int, now: Date) -> String { PairingCopy.expiry(expiresAt: expiresAt, now: now) }
}
