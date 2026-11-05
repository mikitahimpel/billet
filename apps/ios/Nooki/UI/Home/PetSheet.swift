import SwiftUI
import TipKit

/// Mochi's avatar in the room's corner: her face inside a ring that fills toward the next level. A tap opens her sheet.
struct PetButton: View {
    let state: HomeState
    var onPlay: () -> Void
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
                        .trim(from: 0, to: min(max(state.progress, 0.02), 1))
                        .stroke(.honeyGradient, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.5), value: state.progress)
                }
                .glass(.circle, interactive: true)
                .overlay(alignment: .bottom) {
                    Text("Lv.\(state.level)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0x4A2A14))
                        .padding(.horizontal, 7)
                        .frame(height: 17)
                        .background(.honeyGradient, in: .capsule)
                        .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: 1))
                        .contentTransition(.numericText())
                        .offset(y: 8)
                }
                // A little hop each time she is cared for.
                .keyframeAnimator(initialValue: 1.0, trigger: state.petPulse) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    SpringKeyframe(1.12, duration: 0.15)
                    SpringKeyframe(1.0, duration: 0.35)
                }
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(state.petName), Lv. \(state.level)")
        // Both hints live on her portrait; the second waits for the first, so only one shows at a time.
        .popoverTip(PetHint(), arrowEdge: .bottom)
        .popoverTip(TreatHint(), arrowEdge: .bottom)
        .sheet(isPresented: $showsSheet) {
            PetSheet(state: state) {
                showsSheet = false
                onPlay()
            }
            .presentationDetents([.height(372)])
            .presentationBackground(Ink.sheet)
            .presentationDragIndicator(.visible)
        }
    }
}

/// Mochi up close: her level and mood, and ways to look after her.
private struct PetSheet: View {
    let state: HomeState
    var onPlay: () -> Void
    @State private var short = false

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 16) {
                PetPortrait(size: 92)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(state.petName)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("Lv. \(state.level)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: 0x4A2A14))
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(.honeyGradient, in: .capsule)
                            .contentTransition(.numericText())
                    }
                    ProgressCapsule(value: state.progress)
                    Text("\(Int((state.progress * 100).rounded()))% to Lv. \(state.level + 1)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.secondary)
                        .contentTransition(.numericText())
                }
            }

            HStack(spacing: 6) {
                ForEach(state.moods) { mood in
                    MoodChip(mood: mood)
                }
            }

            HStack(spacing: 10) {
                action("Pet", "hand.raised.fill", detail: "+3%") {
                    withAnimation(.spring(duration: 0.4)) { state.pet() }
                }
                action("Treat", "fork.knife", detail: "\(HomeState.treatPrice) coins") {
                    withAnimation(.spring(duration: 0.4)) { short = !state.treat() }
                }
                action("Play", "sparkles", detail: "All her tricks", run: onPlay)
            }
            .haptic(.impact(weight: .light), trigger: state.petPulse)

            Text(short ? "Not enough coins for a treat" : "With you two for \(state.daysTogether) days")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(short ? Color.blushPink : Ink.secondary)
                .contentTransition(.opacity)
        }
        .foregroundStyle(Ink.primary)
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func action(_ title: String, _ symbol: String, detail: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.honeyGradient)
                    .frame(height: 26)
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Ink.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Ink.hairline, lineWidth: 0.5))
        }
        .buttonStyle(PressScaleStyle())
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

struct MoodChip: View {
    let mood: Mood

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: mood.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(mood.tint)
            Text(mood.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background(.white.opacity(0.1), in: .capsule)
        .overlay(Capsule().stroke(Ink.hairline, lineWidth: 0.5))
    }
}
