import SwiftUI
import Design

/// What shows while the room warms up under it: Mochi in her coat on the warm stage, the name arriving on a spring,
/// and three dots that say it is still opening. One clock drives all of it; Reduce Motion holds her at rest and fades.
struct LaunchSplash: View {
    var coat: CatCoat = .current()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var shown = false

    var body: some View {
        ZStack {
            Self.launchColor
            RadialGradient(colors: [Color.honey.opacity(0.4), Color.honeyDeep.opacity(0.18), .clear],
                           center: UnitPoint(x: 0.5, y: 0.42), startRadius: 10, endRadius: 380)
                .scaleEffect(shown || reduceMotion ? 1 : 0.6)
                .opacity(shown ? 1 : 0)
            TimelineView(.animation(paused: reduceMotion)) { context in
                let time = reduceMotion ? 0 : context.date.timeIntervalSince(start)
                VStack(spacing: Space.xs) {
                    CatHeroStage(coat: coat, time: time, moving: !reduceMotion)
                        .frame(width: 300, height: 340)
                        .opacity(shown ? 1 : 0)
                        .offset(y: shown || reduceMotion ? 0 : 14)
                    Text("Ourio")
                        .font(.ourioLargeTitle)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(Ink.text)
                        .tracking(0.5)
                        .shadow(color: Color.honey.opacity(0.35), radius: 12)
                        .opacity(shown ? 1 : 0)
                        .scaleEffect(shown || reduceMotion ? 1 : 0.86)
                        .offset(y: shown || reduceMotion ? 0 : 22)
                        .animation(reduceMotion ? Motion.fade(Motion.standard) : Motion.spring(0.8).delay(0.25),
                                   value: shown)
                    LoadingDots(time: time)
                        .padding(.top, Space.m)
                        .opacity(shown ? 1 : 0)
                }
                .offset(y: -20)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if reduceMotion {
                withAnimation(Motion.fade(Motion.standard)) { shown = true }
            } else {
                // The cat and the glow first; the name lands on a spring a beat later.
                withAnimation(Motion.spring(0.9)) { shown = true }
            }
        }
    }

    /// The launch screen's LaunchBackground color, so the splash takes over without a seam.
    static let launchColor = Color(hex: 0x2A1A12)
}

private struct LoadingDots: View {
    let time: TimeInterval

    var body: some View {
        HStack(spacing: Space.s) {
            ForEach(0..<3) { i in
                let wave = max(0, sin(time * 4 - Double(i) * 0.8))
                Circle()
                    .fill(Color.honey)
                    .frame(width: 7, height: 7)
                    .opacity(0.35 + 0.65 * wave)
                    .offset(y: -4 * wave)
            }
        }
        .frame(height: 12)
    }
}
