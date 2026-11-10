import FeatureGames
import GamesInterface
import OurioShared
import Pet
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let current = (FixedNeeds.fromLaunch ?? needs())?.needs
        let cue = current.flatMap(NeedLevel.cue)
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
                .overlay(alignment: .topTrailing) {
                    // What she wants, only while she wants it; the sheet says the rest.
                    ZStack {
                        if let cue {
                            SymbolBadge(symbol: cue.symbol, tint: cue.tint)
                                .id(cue)
                                .transition(reduceMotion ? AnyTransition.opacity : .scale.combined(with: .opacity))
                        }
                    }
                    .animation(reduceMotion ? Motion.fade() : Motion.spring(), value: cue)
                }
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
        .buttonStyle(PressScaleStyle())
        // Above the portrait, the arrow down at it, so the hint never covers her.
        .hint(PetHint(), arrowEdge: .bottom, target: Circle())
        .hint(TreatHint(), arrowEdge: .bottom, target: Circle())
        .accessibilityLabel("\(state.petName), Lv. \(state.care.level)")
        .accessibilityValue(cue.map { $0.word(.wants) } ?? "")
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

/// Her face and mood, her four needs with the care each takes, the care no need offers, and one closing line.
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
                    NeedList(name: state.petName, needs: current, care: give)
                    moreCare
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

    private func give(_ care: NeedCare) {
        switch care {
        case .game(let game): onPlay(game)
        case .pet: withAnimation(Motion.spring()) { state.care.pet() }
        }
    }

    private func treat() {
        withAnimation(Motion.spring()) { short = !state.shop.treat() }
        if !short { needs()?.feed() }
    }

    /// Smaller than a need's row, so the rows stay what the eye reads first.
    private var moreCare: some View {
        FlowRow {
            ForEach(NeedCare.more, id: \.self) { care in
                PillButton(care.title, symbol: care.symbol) { give(care) }
                    .accessibilityHint(care.hint(name: state.petName))
            }
            Button(action: treat) {
                HStack(spacing: Space.xs) {
                    Image(systemName: "gift.fill")
                    Text("Treat")
                    CoinIcon(size: 14, relativeTo: .callout)
                    Text(ShopModel.treatPrice, format: .number).monospacedDigit()
                }
                .font(.ourioCallout.weight(.semibold))
            }
            .buttonStyle(PillButtonStyle())
            .accessibilityLabel("Treat, \(ShopModel.treatPrice) coins")
            .accessibilityHint("Fills \(state.petName) up more than a pet")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hero(mood: String?) -> some View {
        Card(warm: true) {
            VStack(spacing: Space.s) {
                PetPortrait(size: 96)
                    .keyframeAnimator(initialValue: 1.0, trigger: state.care.petPulse) { view, scale in
                        view.scaleEffect(scale)
                    } keyframes: { _ in
                        SpringKeyframe(1.08, duration: 0.15)
                        SpringKeyframe(1.0, duration: 0.35)
                    }
                Text(mood ?? "Settling in")
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.text)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                HStack(spacing: Space.s) {
                    Chip("Lv. \(state.care.level)", style: .honey)
                        .contentTransition(.numericText())
                    Text(Self.towardNext(level: state.care.level, progress: state.care.progress))
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Level \(state.care.level)")
                .accessibilityValue(
                    "\(Int((state.care.progress * 100).rounded())) percent to level \(state.care.level + 1)")
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The way to her next level in words; the ring on her portrait on Home draws it.
    static func towardNext(level: Int, progress: Double) -> String {
        let next = "Lv. \(level + 1)"
        switch progress {
        case 0.75...: return "Nearly \(next)"
        case 0.4..<0.75: return "Halfway to \(next)"
        default: return "On the way to \(next)"
        }
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
