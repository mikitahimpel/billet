import SwiftUI
import Design

struct LaunchSplash: View {
    @State private var shown = false
    @State private var breathing = false

    var body: some View {
        ZStack {
            Self.launchColor
            RadialGradient(colors: [Color(hex: 0xF4BF7E).opacity(0.55), Color(hex: 0xB36E3A).opacity(0.25), .clear],
                           center: UnitPoint(x: 0.5, y: 0.44), startRadius: 10, endRadius: 360)
                .scaleEffect(shown ? 1 : 0.6)
                .opacity(shown ? 1 : 0)

            VStack(spacing: 4) {
                CatHero(size: 300)
                    .scaleEffect(y: breathing ? 1.015 : 0.995, anchor: .bottom)

                Text("Ourio")
                    .font(.ourioLargeTitle)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(.white)
                    .tracking(0.5)

                LoadingDots()
                    .padding(.top, 18)
            }
            .offset(y: -20)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { shown = true }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathing = true }
        }
    }

    /// The launch screen's LaunchBackground color, so the splash takes over without a seam.
    static let launchColor = Color(hex: 0x2A1A12)
}

private struct LoadingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    let wave = max(0, sin(t * 4 - Double(i) * 0.8))
                    Circle()
                        .fill(Color(hex: 0xFFD9A8))
                        .frame(width: 7, height: 7)
                        .opacity(0.35 + 0.65 * wave)
                        .offset(y: -4 * wave)
                }
            }
        }
        .frame(height: 12)
    }
}
