import SwiftUI
import Design

struct HeartBubble: View {
    let pulse: Int
    @State private var floating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bursts: [Int] = []

    var body: some View {
        ZStack {
            ForEach(bursts, id: \.self) { id in
                FloatingHeart(seed: id)
            }
            VStack(spacing: -1) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: 0xFF7A93))
                    .frame(width: 42, height: 42)
                    .background {
                        Circle().fill(.white.opacity(0.95)).shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    }
                Triangle()
                    .fill(.white.opacity(0.95))
                    .frame(width: 10, height: 6)
            }
            .keyframeAnimator(initialValue: 1.0, trigger: pulse) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.25, duration: 0.14)
                SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
            }
        }
        .offset(y: floating ? -4 : 2)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever()) { floating = true }
        }
        .onChange(of: pulse) { _, new in
            bursts.append(new)
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                bursts.removeAll { $0 == new }
            }
        }
    }
}

private struct FloatingHeart: View {
    let seed: Int
    @State private var rise = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 14))
            .foregroundStyle(Color(hex: 0xFF8FA3))
            .offset(x: rise ? CGFloat((seed * 37) % 50 - 25) : 0, y: rise ? -80 : -10)
            .opacity(rise ? 0 : 1)
            .scaleEffect(rise ? 1.3 : 0.6)
            .onAppear {
                withAnimation(.easeOut(duration: 1.3)) { rise = true }
            }
    }
}

private nonisolated struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
