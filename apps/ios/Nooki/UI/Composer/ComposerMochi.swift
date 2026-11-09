import SwiftUI

struct MochiOnDesk: View {
    /// Changes with every edit; she pats the paper, and gets up when she was sitting.
    let activity: Int
    let paper: CGSize
    @Binding var swiping: Bool

    @State private var sitting = false
    @State private var patTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let fur = Color(hex: 0xA9A29A)
    private static let furDark = Color(hex: 0x8B857E)
    private static let nose = Color(hex: 0xE8A1A8)

    var body: some View {
        ZStack {
            peek
                .offset(x: -paper.width * 0.28, y: -paper.height / 2 - 14)
            paw
                .offset(x: paper.width / 2 - 6, y: paper.height * 0.12)
            if sitting { loaf }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: activity) {
            if sitting { withAnimation(.snappy) { sitting = false } }
            if !reduceMotion { patTick += 1 }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.6)) { sitting = true }
        }
    }

    private var peek: some View {
        ZStack {
            Peak().fill(Self.fur).frame(width: 26, height: 24).offset(x: -22, y: -2).rotationEffect(.degrees(-12))
            Peak().fill(Self.fur).frame(width: 26, height: 24).offset(x: 22, y: -2).rotationEffect(.degrees(12))
            Peak().fill(Self.nose.opacity(0.7)).frame(width: 12, height: 12).offset(x: -22, y: 3)
                .rotationEffect(.degrees(-12))
            Peak().fill(Self.nose.opacity(0.7)).frame(width: 12, height: 12).offset(x: 22, y: 3)
                .rotationEffect(.degrees(12))
            Capsule().fill(Self.fur).frame(width: 78, height: 30).offset(y: 14)
        }
        .offset(y: sitting ? 6 : 0)
        .animation(.snappy, value: sitting)
    }

    private var paw: some View {
        ZStack {
            Capsule().fill(Self.fur).frame(width: 70, height: 26)
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in Capsule().fill(Self.furDark).frame(width: 2, height: 9) }
            }
            .offset(x: -22)
        }
        .rotationEffect(.degrees(-4))
        .keyframeAnimator(initialValue: 0.0, trigger: swiping ? -1 : patTick) { view, value in
            view.offset(x: swiping ? -paper.width * 0.5 * value : 18 - 18 * value)
        } keyframes: { _ in
            LinearKeyframe(0.0, duration: 0.01)
            SpringKeyframe(1.0, duration: 0.25)
            SpringKeyframe(0.0, duration: 0.3)
        }
    }

    private var loaf: some View {
        ZStack {
            Ellipse().fill(Self.fur).frame(width: 74, height: 46)
            Peak().fill(Self.fur).frame(width: 18, height: 18).offset(x: -16, y: -26)
            Peak().fill(Self.fur).frame(width: 18, height: 18).offset(x: 6, y: -26)
            Capsule().fill(Self.furDark).frame(width: 30, height: 8).offset(x: 24, y: 8).rotationEffect(.degrees(-20))
        }
        .offset(x: paper.width * 0.26, y: -paper.height / 2 + 10)
        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
    }
}
