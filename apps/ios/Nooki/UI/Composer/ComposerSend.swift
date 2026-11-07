import AudioToolbox
import SwiftUI
import Design

/// The delivery: the sticky is peeled off and slapped away; on the desk and the papers the note folds into a paper
/// plane and flies off. Haptic and a sound go with it; under Reduce Motion the note just goes.
struct SendFlight: ViewModifier {
    let style: ComposerStyle
    let color: Color
    /// 0 on the desk, 1 at the end.
    let progress: Double

    func body(content: Content) -> some View {
        switch style {
        case .sticky:
            content
                .rotationEffect(.degrees(progress < 0.35 ? -6 * progress / 0.35 : 4 * (progress - 0.35)))
                .offset(x: progress * 40, y: progress < 0.35 ? -18 * progress / 0.35 : 900 * pow((progress - 0.35) / 0.65, 2))
                .scaleEffect(progress < 0.35 ? 1 : 1 - 0.25 * (progress - 0.35) / 0.65)
        case .desk, .papers:
            ZStack {
                content
                    .scaleEffect(max(0.05, 1 - progress * 3.2))
                    .opacity(progress < 0.3 ? 1 : 0)
                Image(systemName: "paperplane.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .foregroundStyle(color)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
                    .rotationEffect(.degrees(-20))
                    .scaleEffect(progress < 0.25 ? 0.2 : 1 - (progress - 0.25) * 0.5)
                    .opacity(progress < 0.25 ? 0 : 1)
                    .offset(x: progress < 0.3 ? 0 : 520 * pow((progress - 0.3) / 0.7, 1.6),
                            y: progress < 0.3 ? 0 : -640 * pow((progress - 0.3) / 0.7, 1.6))
            }
        }
    }

    static let duration = 0.85

    @MainActor static func playSound() {
        AudioServicesPlaySystemSound(1001)
    }
}

extension View {
    func sendFlight(style: ComposerStyle, color: Color, progress: Double) -> some View {
        modifier(SendFlight(style: style, color: color, progress: progress))
    }
}
