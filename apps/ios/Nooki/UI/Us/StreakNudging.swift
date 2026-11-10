import Design
import OurioShared
import ProfileInterface
import SwiftUI

/// Keeps the evening streak nudge in step with the streak and the Settings switch.
struct StreakNudging: ViewModifier {
    let streak: StreakStore
    @AppStorage(AppSettings.streakNudgeKey) private var enabled = true

    private struct Key: Equatable {
        let streak: LoveStreak
        let enabled: Bool
    }

    func body(content: Content) -> some View {
        content.task(id: Key(streak: streak.streak, enabled: enabled)) {
            await StreakNudge.reschedule(streak.streak, enabled: enabled, catName: CatProfile.name())
        }
    }
}
