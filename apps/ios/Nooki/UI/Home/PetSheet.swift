import FeatureGames
import SwiftUI
import TipKit

/// Mochi's avatar in the room's corner: her face inside a ring that fills toward the next level. A tap opens her sheet.
struct PetButton: View {
    let state: HomeState
    /// Mochi's needs, once her brain is running in the room.
    var needs: () -> PetNeedsSource?
    /// Starts one of the mini-games, once the sheet is down.
    var onPlay: (MiniGame) -> Void
    @State private var showsSheet = false
    /// The sheet's content height, measured, so the sheet ends just under its last line.
    @State private var sheetHeight: CGFloat = 520
    @Environment(Hints.self) private var hints

    var body: some View {
        Button {
            showsSheet = true
            hints.done(PetHint())
        } label: {
            PetPortrait(size: 58)
                .padding(3)
                .overlay {
                    Circle()
                        .trim(from: 0, to: min(max(state.care.progress, 0.02), 1))
                        .stroke(.honeyGradient, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.5), value: state.care.progress)
                }
                .glass(.circle, interactive: true)
                .overlay(alignment: .bottom) {
                    Text("Lv.\(state.care.level)")
                        .font(.nookiMicro)
                        .foregroundStyle(Ink.heroInk)
                        .padding(.horizontal, 7)
                        .frame(height: 17)
                        .background(.honeyGradient, in: .capsule)
                        .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: 1))
                        .contentTransition(.numericText())
                        .offset(y: 8)
                }
                // A little hop each time she is cared for.
                .keyframeAnimator(initialValue: 1.0, trigger: state.care.petPulse) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    SpringKeyframe(1.12, duration: 0.15)
                    SpringKeyframe(1.0, duration: 0.35)
                }
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(state.petName), Lv. \(state.care.level)")
        .accessibilityIdentifier("pet")
        // Both hints live on her portrait; the second waits for the first, so only one shows at a time.
        .popoverTip(PetHint(), arrowEdge: .bottom)
        .popoverTip(TreatHint(), arrowEdge: .bottom)
        .onChange(of: state.showsPetSheet) { _, asked in
            guard asked else { return }
            showsSheet = true
            state.showsPetSheet = false
        }
        .sheet(isPresented: $showsSheet) {
            PetSheet(state: state, needs: needs, height: $sheetHeight) { game in
                showsSheet = false
                onPlay(game)
            }
            .presentationDetents([.height(sheetHeight)])
            .presentationBackground(Ink.screen)
            .presentationDragIndicator(.visible)
        }
    }
}

/// Mochi up close: her face big on a warm stage, her name, mood and level, her four needs, and the things to do for
/// her. It scrolls only when its content is taller than the screen allows.
private struct PetSheet: View {
    let state: HomeState
    var needs: () -> PetNeedsSource?
    @Binding var height: CGFloat
    var onPlay: (MiniGame) -> Void
    @State private var short = false

    var body: some View {
        ScrollView {
            // The brain starts after the room has loaded and keeps changing; look again each second.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let current = (FixedNeeds.fromLaunch ?? needs())?.needs
                VStack(spacing: Space.l) {
                    hero(mood: current?.moodLine(name: state.petName))
                    NeedBars(name: state.petName, needs: current)
                    PetActions(
                        treat: {
                            withAnimation(.spring(duration: 0.4)) { short = !state.shop.treat() }
                            if !short { needs()?.feed() }
                        },
                        pet: { withAnimation(.spring(duration: 0.4)) { state.care.pet() } },
                        play: onPlay
                    )
                    Text(short ? "Not enough coins for a treat" : "With you two for \(state.daysTogether) days")
                        .font(.nookiCaption)
                        .foregroundStyle(short ? Ink.accentText : Ink.textSecondary)
                        .contentTransition(.opacity)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.section)
                .padding(.bottom, Space.l)
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .haptic(.impact(weight: .light), trigger: state.care.petPulse)
    }

    private func hero(mood: String?) -> some View {
        VStack(spacing: Space.s) {
            PetPortrait(size: 112)
                .shadow(color: Color(hex: 0x8A3A1E).opacity(0.35), radius: 14, y: 8)
                .keyframeAnimator(initialValue: 1.0, trigger: state.care.petPulse) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    SpringKeyframe(1.08, duration: 0.15)
                    SpringKeyframe(1.0, duration: 0.35)
                }
                .padding(.top, Space.s)
            Text(state.petName)
                .font(.nookiLargeTitle)
                .foregroundStyle(Ink.heroInk)
            if let mood {
                Text(mood)
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.heroInk.opacity(0.75))
                    .contentTransition(.opacity)
            }
            HStack(spacing: Space.s) {
                Text("Lv. \(state.care.level)")
                    .font(.nookiMicro)
                    .foregroundStyle(Ink.heroInk)
                    .padding(.horizontal, Space.s)
                    .frame(height: 22)
                    .background(.white.opacity(0.7), in: .capsule)
                    .contentTransition(.numericText())
                LevelTrack(value: state.care.progress)
                Text("\(Int((state.care.progress * 100).rounded()))%")
                    .font(.nookiMicro)
                    .foregroundStyle(Ink.heroInk.opacity(0.75))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, Space.l)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Level \(state.care.level)")
            .accessibilityValue("\(Int((state.care.progress * 100).rounded())) percent to level \(state.care.level + 1)")
        }
        .padding(.bottom, Space.l)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFFE2B0), Color(hex: 0xF6B77A)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    // Lamplight from above, as on her in the room.
                    RadialGradient(colors: [.white.opacity(0.6), .clear], center: UnitPoint(x: 0.5, y: 0.2),
                                   startRadius: 0, endRadius: 150)
                        .clipShape(.rect(cornerRadius: Radius.hero, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                        .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        }
    }
}

/// The level bar on the warm stage: honey on a white groove.
private struct LevelTrack: View {
    let value: Double

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.55))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(LinearGradient(colors: [Color.honey, .honeyDeep], startPoint: .top, endPoint: .bottom))
                        .frame(width: max(proxy.size.height, proxy.size.width * min(max(value, 0), 1)))
                }
            }
            .frame(height: 10)
            .animation(.spring(duration: 0.5), value: value)
    }
}

/// Her face (Tools/make_portrait.py) on a warm disc.
private struct PetPortrait: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = UIImage(named: CatCoat.current().avatar) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "cat.fill").font(.system(size: size * 0.45)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .background(RadialGradient(colors: [Color(hex: 0xFFF4E4), Color(hex: 0xF2C08A)], center: .init(x: 0.5, y: 0.35),
                                   startRadius: 0, endRadius: size * 0.75))
        .clipShape(.circle)
        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: size > 70 ? 3 : 2))
    }
}
