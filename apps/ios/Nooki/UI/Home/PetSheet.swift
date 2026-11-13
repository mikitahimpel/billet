import FeatureGames
import FeatureShop
import GamesInterface
import MomentsInterface
import WidgetInterface
import WidgetUI
import Pet
import RoomInterface
import SwiftUI
import Design
import TipKit
import UsInterface

struct PetButton: View {
    let state: HomeState
    /// Mochi's needs, once her brain is running in the room.
    var needs: () -> PetNeedsSource?
    /// Starts one of the mini-games, once the sheet is down.
    var onPlay: (MiniGame) -> Void
    @State private var showsSheet = false
    /// Bumped when a need starts to want something, so its ring pulses once.
    @State private var asks = 0
    @Environment(Hints.self) private var hints
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let current = (FixedNeeds.fromLaunch ?? needs())?.needs
        let cue = current.flatMap(NeedLevel.cue)
        Button {
            showsSheet = true
            hints.done(PetHint())
            hints.done(NeedsHint())
        } label: {
            PetPortrait(size: 58)
                .padding(Space.xs)
                .overlay {
                    // Her four needs, an arc each; the sheet a tap opens says the rest.
                    if let current {
                        SegmentedRing(PetNeed.ringOrder.map { .init(value: current[$0], tint: $0.tint) })
                            .keyframeAnimator(initialValue: 1.0, trigger: asks) { view, scale in
                                view.scaleEffect(scale)
                            } keyframes: { _ in
                                SpringKeyframe(1.14, duration: 0.2)
                                SpringKeyframe(1.0, duration: 0.4)
                            }
                    }
                }
                .glass(.circle, role: .control)
                .overlay(alignment: .topTrailing) {
                    // What she wants, only while she wants it.
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
                    // Names the button: what she asks for, or simply that her needs are here.
                    Text(cue?.ask ?? "Needs")
                        .font(.ourioMicro)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .frame(height: 17)
                        .glassBadge()
                        .contentTransition(.opacity)
                        .offset(y: 8)
                }
                .keyframeAnimator(initialValue: 1.0, trigger: state.care.petPulse) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    SpringKeyframe(1.12, duration: 0.15)
                    SpringKeyframe(1.0, duration: 0.35)
                }
                // Chrome over the room caps its text as the header does, so the tag never outgrows its pill.
                // On the label only: the sheet below keeps the full range.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .buttonStyle(PressScaleStyle())
        // Above the portrait, the arrow down at it, so the hint never covers her.
        .hint(PetHint(), arrowEdge: .bottom, target: Circle())
        .hint(NeedsHint(), arrowEdge: .bottom, target: Circle())
        .hint(TreatHint(), arrowEdge: .bottom, target: Circle())
        .accessibilityLabel("\(state.petName)'s needs")
        .accessibilityValue(current.map(Self.spoken) ?? "")
        .accessibilityHint(state.pronouns.say(.opensNeeds))
        .accessibilityIdentifier("pet")
        .onChange(of: cue) { _, cue in
            if cue != nil, !reduceMotion { asks += 1 }
        }
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

/// Mochi's sheet over the room: ``MochiSheetContent`` with her live status, her care wired to the room and the shop.
private struct PetSheet: View {
    let state: HomeState
    var needs: () -> PetNeedsSource?
    var onPlay: (MiniGame) -> Void
    @State private var short = false
    /// What she said to the care she turned down, for a few seconds.
    @State private var turnedDown: String?
    @State private var declines = 0
    @State private var now = Date()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let source = FixedNeeds.fromLaunch ?? needs()
        BilletSheet(state.petName, size: .fit) {
            MochiSheetContent(name: state.petName, pronouns: state.pronouns, status: source?.status ?? CatStatus(), level: state.care.level,
                              progress: state.care.progress, days: state.daysTogether, care: give,
                              declined: { declined($0, source: source) },
                              choosePronouns: { state.choosePronouns($0) }) {
                PetPortrait(size: 88)
                    .keyframeAnimator(initialValue: 0.0, trigger: declines) { view, turn in
                        view.rotationEffect(.degrees(turn))
                    } keyframes: { _ in
                        if !reduceMotion {
                            LinearKeyframe(-5, duration: 0.08)
                            LinearKeyframe(5, duration: 0.12)
                            LinearKeyframe(-3, duration: 0.1)
                            LinearKeyframe(0, duration: 0.08)
                        }
                    }
                    .keyframeAnimator(initialValue: 1.0, trigger: state.care.petPulse) { view, scale in
                        view.scaleEffect(scale)
                    } keyframes: { _ in
                        SpringKeyframe(1.08, duration: 0.15)
                        SpringKeyframe(1.0, duration: 0.35)
                    }
            } extraCare: {
                moreCare(needsKnown: source?.needs != nil)
            }
        }
        .haptic(.impact(weight: .light), trigger: state.care.petPulse)
        .haptic(.rejected, trigger: declines)
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { now = $0 }
        // A buy the coins don't cover opens the Coins sheet, which can't show over this one.
        .onChange(of: state.shop.coinsAsk) { _, ask in if ask != nil { dismiss() } }
    }

    private func declined(_ care: NeedCare, source: PetNeedsSource?) -> String? {
        care.declined(state.care.gate.verdict(care.kind, needs: source?.status.needs, now: now), now: now)
    }

    /// She turns it down: said where it was asked for, with a shake and a soft buzz, and nothing is given or counted.
    private func decline(_ words: String) {
        declines += 1
        withAnimation(Motion.spring()) { turnedDown = words }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(Motion.spring()) { if turnedDown == words { turnedDown = nil } }
        }
    }

    private func give(_ care: NeedCare) {
        let source = FixedNeeds.fromLaunch ?? needs()
        let at = Date()
        let verdict = state.care.attempt(care.kind, needs: source?.status.needs, now: at)
        if let words = care.declinedSentence(verdict, now: at, name: state.petName) {
            decline(words)
            return
        }
        switch care {
        case .game(let game): onPlay(game)
        case .pet: withAnimation(Motion.spring()) { state.care.pet() }
        }
    }

    private func treat() {
        let source = FixedNeeds.fromLaunch ?? needs()
        let at = Date()
        let verdict = state.care.gate.verdict(.treat, needs: source?.status.needs, now: at)
        if !verdict.isOpen {
            let words = verdict == .refused(.met, until: nil) ? "\(state.petName) is too full for a treat" : "\(state.petName) has had a lot of treats. A little rest"
            decline(words)
            return
        }
        withAnimation(Motion.spring()) { short = !state.shop.treat() }
        if !short {
            state.care.attempt(.treat, needs: source?.status.needs, now: at)
            needs()?.feed()
        }
    }

    /// Smaller than a need's tile, so the tiles stay what the eye reads first.
    private func moreCare(needsKnown: Bool) -> some View {
        let source = FixedNeeds.fromLaunch ?? needs()
        return VStack(alignment: .leading, spacing: Space.s) {
            FlowRow {
                ForEach(NeedCare.extra(needsKnown: needsKnown), id: \.self) { care in
                    PillButton(care.title, symbol: care.symbol) { give(care) }
                        .opacity(declined(care, source: source) == nil ? 1 : 0.55)
                        .accessibilityHint(declined(care, source: source) ?? care.hint(name: state.petName))
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
            if let turnedDown {
                Text(turnedDown)
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.accentText)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isStaticText)
            }
            if short {
                Text("Not enough coins for a treat")
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.accentText)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PetButton {
    /// Her four needs for VoiceOver, in the order her sheet shows them.
    nonisolated static func spoken(_ needs: PetNeeds) -> String {
        PetNeed.displayOrder.map { "\($0.title) \(PetNeed.percent(needs[$0])) percent" }.joined(separator: ", ")
    }
}

/// Her face (Tools/make_portrait.py) on a warm disc.
struct PetPortrait: View {
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
