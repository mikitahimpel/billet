import SwiftUI
import TipKit

/// Mochi's avatar in the room's corner: her face inside a ring that fills toward the next level. A tap opens her sheet.
struct PetButton: View {
    let state: HomeState
    /// Mochi's needs, once her brain is running in the room.
    var needs: () -> PetNeedsSource?
    var onPlay: () -> Void
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
            PetSheet(state: state, needs: needs, height: $sheetHeight) {
                showsSheet = false
                onPlay()
            }
            .presentationDetents([.height(sheetHeight)])
            .presentationBackground(Ink.sheet)
            .presentationDragIndicator(.visible)
        }
    }
}

/// Mochi up close: her level, her four needs, and the way to fill each.
private struct PetSheet: View {
    let state: HomeState
    var needs: () -> PetNeedsSource?
    @Binding var height: CGFloat
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

            // The brain starts after the room has loaded and keeps changing; look again each second.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                NeedBars(
                    name: state.petName,
                    needs: (FixedNeeds.fromLaunch ?? needs())?.needs,
                    feed: {
                        withAnimation(.spring(duration: 0.4)) { short = !state.treat() }
                        if !short { needs()?.feed() }
                    },
                    pet: { withAnimation(.spring(duration: 0.4)) { state.pet() } },
                    play: onPlay
                )
            }
            .haptic(.impact(weight: .light), trigger: state.petPulse)

            Text(short ? "Not enough coins for a treat" : "With you two for \(state.daysTogether) days")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.secondary)
                .contentTransition(.opacity)
        }
        .foregroundStyle(Ink.primary)
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
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
