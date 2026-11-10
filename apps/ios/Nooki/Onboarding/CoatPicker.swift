import SwiftUI
import Design

/// A tap on a chip or a swipe across the cat changes the coat; the cat cross-fades.
struct CoatPicker: View {
    @Binding var coat: CatCoat
    /// The cat's height; nil to fill the height the rest leaves, between 170 and 440.
    var stageHeight: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Space.l) {
            stage
                .gesture(swipe)
                .accessibilityElement()
                .accessibilityLabel(Text("Your cat: \(coat.title)"))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: step(1)
                    case .decrement: step(-1)
                    @unknown default: break
                    }
                }
            Text(coat.title)
                .font(.ourioTitle)
                .foregroundStyle(Ink.text)
                .contentTransition(.opacity)
                .accessibilityHidden(true)
            chips
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35), value: coat)
    }

    @ViewBuilder private var stage: some View {
        if let stageHeight {
            CatStage(coat: coat, height: stageHeight)
        } else {
            GeometryReader { geometry in CatStage(coat: coat, height: geometry.size.height) }
                .frame(minHeight: 170, maxHeight: 440)
        }
    }

    private var chips: some View {
        // A plain Grid, not a lazy one: the step measures the chips to see whether everything fits.
        let rows = stride(from: 0, to: CatCoat.allCases.count, by: 3).map { Array(CatCoat.allCases[$0..<min($0 + 3, CatCoat.allCases.count)]) }
        return Grid(horizontalSpacing: Space.m, verticalSpacing: Space.m) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { item in
                        Button { coat = item } label: { CoatChip(coat: item, picked: item == coat) }
                            .buttonStyle(PressScaleStyle())
                            .accessibilityLabel(Text(item.title))
                            .accessibilityAddTraits(item == coat ? [.isSelected] : [])
                    }
                }
            }
        }
        .padding(.horizontal, Space.gutter)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24).onEnded { drag in
            guard abs(drag.translation.width) > abs(drag.translation.height), abs(drag.translation.width) > 40 else { return }
            step(drag.translation.width < 0 ? 1 : -1)
        }
    }

    private func step(_ by: Int) {
        let all = CatCoat.allCases
        guard let at = all.firstIndex(of: coat) else { return }
        coat = all[(at + by + all.count) % all.count]
    }
}

/// billet-gpu's render of the seated splat Mochi: same pose, light and framing for every coat.
struct CatStage: View {
    let coat: CatCoat
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the render frames her: ears at 5% and paws at 94.75% of its 3:4 height.
    private static let earsAt = 0.05, pawsAt = 0.9475

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(RadialGradient(colors: [Color.honey.opacity(0.36), Color.honey.opacity(0.1), .clear],
                                     center: UnitPoint(x: 0.42, y: 0.45), startRadius: 0, endRadius: height * 0.55))
                .frame(width: height * 1.2, height: height * 1.2)
                .offset(y: -height * 0.04)
            Ellipse()
                .fill(.black.opacity(0.2))
                .frame(width: height * 0.7, height: ground * 1.1)
                .blur(radius: height * 0.03)
                .offset(y: ground * 0.1)
            Ellipse()
                .fill(.black.opacity(0.5))
                .frame(width: height * 0.4, height: ground * 0.4)
                .blur(radius: height * 0.012)
                .offset(y: -ground * 0.05)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let breath = reduceMotion ? 0 : sin(t * 2 * .pi / 3.4)
                portrait
                    .padding(.bottom, ground / 2)
                    .scaleEffect(x: 1 - 0.006 * breath, y: 1 + 0.012 * breath, anchor: .bottom)
                    .rotationEffect(.degrees(reduceMotion ? 0 : 0.8 * sin(t * 2 * .pi / 7.5)), anchor: .bottom)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    /// The band under her paws that holds the shadow.
    private var ground: CGFloat { height * 0.1 }
    /// Her height, ears to paws; the paws stand in the middle of the band.
    private var cat: CGFloat { height - ground / 2 }

    private var portrait: some View {
        let image = Image(uiImage: UIImage(named: coat.portrait) ?? UIImage()).resizable().interpolation(.high)
        let tall = cat / (Self.pawsAt - Self.earsAt)
        return image
            .scaledToFit()
            .overlay {
                LinearGradient(colors: [Color(hex: 0xFFD7A6).opacity(0.55), .clear, Color(hex: 0x5A3420).opacity(0.3)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .blendMode(.softLight)
                    .mask(image.scaledToFit())
            }
            .shadow(color: Color(hex: 0xFFB866).opacity(0.3), radius: height * 0.03, x: -height * 0.015)
            .frame(height: tall)
            .offset(y: tall * (1 - Self.pawsAt))
            .frame(height: cat, alignment: .bottom)
            .id(coat)
            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)),
                                    removal: .opacity))
    }
}

struct CoatChip: View {
    let coat: CatCoat
    let picked: Bool
    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 56

    var body: some View {
        VStack(spacing: Space.s) {
            CoatSwatchShape(swatch: coat.swatch)
                .frame(width: size, height: size)
                .padding(Space.xs)
                .overlay(Circle().stroke(picked ? Color.honey : .clear, lineWidth: 2.5))
                .scaleEffect(picked ? 1.06 : 1)
            Text(coat.title)
                .font(.ourioCaption)
                .foregroundStyle(picked ? Ink.text : Ink.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: Size.control)
        .contentShape(.rect)
    }
}

struct CoatSwatchShape: View {
    let swatch: CatCoat.Swatch

    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2
            let disc = Path(ellipseIn: CGRect(origin: .zero, size: size))
            context.clip(to: disc)
            context.fill(disc, with: .color(swatch.base))
            for mark in swatch.marks {
                let rect = CGRect(x: mark.rect.minX * size.width, y: mark.rect.minY * size.height,
                                  width: mark.rect.width * size.width, height: mark.rect.height * size.height)
                var shape = Path(ellipseIn: rect)
                if mark.angle != 0 {
                    shape = shape.applying(CGAffineTransform(translationX: -rect.midX, y: -rect.midY)
                        .concatenating(CGAffineTransform(rotationAngle: mark.angle))
                        .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY)))
                }
                context.fill(shape, with: .color(mark.color))
            }
            context.fill(disc, with: .radialGradient(Gradient(colors: [.white.opacity(0.5), .white.opacity(0)]),
                                                     center: CGPoint(x: r * 0.62, y: r * 0.55), startRadius: 0, endRadius: r * 0.9))
            context.fill(disc, with: .radialGradient(Gradient(colors: [.black.opacity(0), .black.opacity(0.3)]),
                                                     center: CGPoint(x: r * 0.85, y: r * 0.8), startRadius: r * 0.7, endRadius: r * 1.45))
        }
        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        .accessibilityHidden(true)
    }
}

extension CatCoat {
    /// Picked from billet-gpu's renders.
    struct Swatch {
        struct Mark {
            /// In the unit square of the chip.
            let rect: CGRect
            var angle: CGFloat = 0
            let color: Color
        }

        let base: Color
        var marks: [Mark] = []
    }

    var swatch: Swatch {
        func stripes(_ color: Color) -> [Swatch.Mark] {
            [0.18, 0.44, 0.7].map { Swatch.Mark(rect: CGRect(x: -0.1, y: $0, width: 1.2, height: 0.12), angle: -0.35, color: color) }
        }
        return switch self {
        case .grey: Swatch(base: Color(hex: 0xB9B7B4), marks: stripes(Color(hex: 0x6F6C69)))
        case .ginger: Swatch(base: Color(hex: 0xF2A466), marks: stripes(Color(hex: 0xD9773E)))
        case .cream: Swatch(base: Color(hex: 0xF4E6D2), marks: stripes(Color(hex: 0xE3CBAA)))
        case .tuxedo: Swatch(base: Color(hex: 0x2C2A2C),
                             marks: [Swatch.Mark(rect: CGRect(x: 0.22, y: 0.52, width: 0.56, height: 0.7), color: Color(hex: 0xF7F2EC))])
        case .black: Swatch(base: Color(hex: 0x262426))
        case .calico: Swatch(base: Color(hex: 0xF7F2EC), marks: [
            Swatch.Mark(rect: CGRect(x: -0.15, y: -0.1, width: 0.7, height: 0.6), angle: 0.4, color: Color(hex: 0xE8934C)),
            Swatch.Mark(rect: CGRect(x: 0.5, y: 0.25, width: 0.65, height: 0.5), angle: -0.5, color: Color(hex: 0x2E2A2A)),
        ])
        }
    }
}
