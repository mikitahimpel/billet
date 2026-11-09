import FeatureGames
import GamesInterface
import SwiftUI
import Design
import TipKit

struct PetButton: View {
    let state: HomeState
    /// Mochi's needs, once her brain is running in the room.
    var needs: () -> PetNeedsSource?
    /// Starts one of the mini-games, once the sheet is down.
    var onPlay: (MiniGame) -> Void
    @State private var showsSheet = false
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
                .glass(.circle, role: .control)
                .overlay(alignment: .bottom) {
                    Text("Lv.\(state.care.level)")
                        .font(.ourioMicro)
                        .padding(.horizontal, 7)
                        .frame(height: 17)
                        .glassBadge()
                        .contentTransition(.numericText())
                        .offset(y: 8)
                }
                .keyframeAnimator(initialValue: 1.0, trigger: state.care.petPulse) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    SpringKeyframe(1.12, duration: 0.15)
                    SpringKeyframe(1.0, duration: 0.35)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(state.petName), Lv. \(state.care.level)")
        .accessibilityIdentifier("pet")
        .onChange(of: state.showsPetSheet) { _, asked in
            guard asked else { return }
            showsSheet = true
            state.showsPetSheet = false
        }
        .sheet(isPresented: $showsSheet) {
            PetSheet(state: state, needs: needs) { game in
                showsSheet = false
                onPlay(game)
            }
        }
    }
}

/// Scrolls only when its content is taller than the screen allows.
private struct PetSheet: View {
    let state: HomeState
    var needs: () -> PetNeedsSource?
    var onPlay: (MiniGame) -> Void
    @State private var short = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BilletSheet(state.petName, size: .fit) {
            // The brain starts after the room has loaded and keeps changing; look again each second.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let current = (FixedNeeds.fromLaunch ?? needs())?.needs
                VStack(spacing: Space.m) {
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
                        .font(.ourioCaption)
                        .foregroundStyle(short ? Ink.accentText : Ink.textSecondary)
                        .contentTransition(.opacity)
                }
            }
        }
        .haptic(.impact(weight: .light), trigger: state.care.petPulse)
        // A buy the coins don't cover opens the Coins sheet, which can't show over this one.
        .onChange(of: state.shop.coinsAsk) { _, ask in if ask != nil { dismiss() } }
    }

    private func hero(mood: String?) -> some View {
        VStack(spacing: 6) {
            PetPortrait(size: 96)
                .shadow(color: Color(hex: 0x8A3A1E).opacity(0.35), radius: 14, y: 8)
                .keyframeAnimator(initialValue: 1.0, trigger: state.care.petPulse) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    SpringKeyframe(1.08, duration: 0.15)
                    SpringKeyframe(1.0, duration: 0.35)
                }
            if let mood {
                Text(mood)
                    .font(.ourioCallout)
                    .foregroundStyle(Ink.textSecondary)
                    .contentTransition(.opacity)
            }
            HStack(spacing: Space.s) {
                Chip("Lv. \(state.care.level)", style: .honey)
                    .contentTransition(.numericText())
                LevelTrack(value: state.care.progress)
                Text("\(Int((state.care.progress * 100).rounded()))%")
                    .font(.ourioMicro)
                    .foregroundStyle(Ink.textSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, Space.l)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Level \(state.care.level)")
            .accessibilityValue("\(Int((state.care.progress * 100).rounded())) percent to level \(state.care.level + 1)")
        }
        .padding(.vertical, Space.l)
        .frame(maxWidth: .infinity)
        .cardSurface(warm: true)
    }
}

private struct LevelTrack: View {
    let value: Double

    var body: some View {
        Capsule()
            .fill(Ink.surfaceRaised)
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
                Image(systemName: "cat.fill").font(.title).foregroundStyle(Ink.heroInk)
            }
        }
        .frame(width: size, height: size)
        .background(RadialGradient(colors: [Color(hex: 0xFFF4E4), Color(hex: 0xF2C08A)], center: .init(x: 0.5, y: 0.35),
                                   startRadius: 0, endRadius: size * 0.75))
        .clipShape(.circle)
        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: size > 70 ? 3 : 2))
    }
}
