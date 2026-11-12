import Design
import MomentsInterface
import WidgetInterface
import WidgetUI
import ProfileInterface
import SwiftUI
import UsInterface

/// Keeps the evening streak nudge in step with the streak and the Settings switch.
struct StreakNudging: ViewModifier {
    let streak: StreakStore
    @AppStorage(AppSettings.streakNudgeKey, store: StreakNudge.settings) private var enabled = true

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
