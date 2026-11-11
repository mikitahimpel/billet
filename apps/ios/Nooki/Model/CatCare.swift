import MomentsInterface
import Observation
import WidgetInterface
import WidgetUI
import UsInterface

/// Mochi's care on this phone: pets, treats and the bar that fills her level. The level lives in the shared wallet
/// file, so the widgets show the same one.
@Observable
final class CatCare {
    @ObservationIgnored private let wallet: WalletStore
    @ObservationIgnored private let streak: StreakStore

    /// Bumped by every pet, treat and buy; the room's cat purrs at the next look.
    var petPulse = 0
    /// Treats given since launch.
    private(set) var treatsGiven = 0
    /// Pets given in the app, not from the widgets; each may reach the pair's journal.
    private(set) var petsGiven = 0

    init(wallet: WalletStore, streak: StreakStore) {
        self.wallet = wallet
        self.streak = streak
    }

    var level: Int { wallet.wallet.level }
    var progress: Double { wallet.wallet.progress }

    /// How much of her bar one pet fills.
    nonisolated static let petFill = 0.03

    /// The way to her next level in words: the pets it still takes, or that it is one pet off.
    nonisolated static func towardNext(level: Int, progress: Double) -> String {
        let left = 1 - (progress.isFinite ? min(max(progress, 0), 1) : 0)
        // Less a hair, so 0.6 of the bar is 20 pets and not 21 by rounding.
        let pets = max(1, Int((left / petFill - 1e-9).rounded(.up)))
        return pets == 1 ? "One more pet to Lv. \(level + 1)" : "\(pets) pets to Lv. \(level + 1)"
    }

    func pet() {
        petsGiven += 1
        petPulse += 1
        fill(Self.petFill)
        streak.record()
    }

    /// A treat that was paid for: it fills more of her bar than a pet.
    func fed() {
        treatsGiven += 1
        petPulse += 1
        fill(0.1)
        streak.record()
    }

    func notice() {
        petPulse += 1
    }

    private func fill(_ amount: Double) {
        wallet.update {
            $0.progress += amount
            if $0.progress >= 1 {
                $0.progress -= 1
                $0.level += 1
            }
        }
    }
}
