import Design
import SwiftUI
import UIKit

/// The hero Mochi's pictures for one coat, from `Tools/bake_hero.py`: the seated splat at rest, 3:4, and the patches
/// that close her lids and flick her ear. A patch replaces its rectangle of the rest image; outside it the frames are
/// the rest image, pixel for pixel.
nonisolated struct HeroImages: @unchecked Sendable {
    let rest: UIImage
    /// Half and fully shut.
    let blink: [UIImage]
    /// Half and fully out.
    let ear: [UIImage]

    /// The patches' rectangles as fractions of the rest image, printed by the bake.
    static let blinkRect = CGRect(x: 0.32222, y: 0.20486, width: 0.44352, height: 0.22639)
    static let earRect = CGRect(x: 0.23889, y: 0.10764, width: 0.21019, height: 0.16736)

    /// Read and decoded off the main actor, so the first frames never wait on a decode.
    static func load(_ coat: CatCoat, from bundle: Bundle = .main) async -> HeroImages? {
        let names = ["Hero", "HeroBlink1", "HeroBlink2", "HeroEar1", "HeroEar2"]
        let urls = names.compactMap { bundle.url(forResource: "\($0)-\(coat.rawValue)", withExtension: "webp") }
        guard urls.count == names.count else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> HeroImages? in
            let images = urls.compactMap { UIImage(contentsOfFile: $0.path)?.preparingForDisplay() }
            guard images.count == urls.count else { return nil }
            return HeroImages(rest: images[0], blink: Array(images[1...2]), ear: Array(images[3...4]))
        }.value
    }
}

/// Mochi on a warm stage: a glow behind her, drifting dust, a contact shadow, a honey rim light from behind on her
/// edges, and the loop of `HeroMotion` (breath, sway, blinks, an ear flick, a hop on `pokedAt`). The parent's clock
/// drives it; with `moving` false she rests and nothing drifts. Each layer sways by its own amount, for depth.
struct CatHeroStage: View {
    let coat: CatCoat
    /// Seconds since the stage appeared.
    let time: TimeInterval
    var pokedAt: TimeInterval?
    var moving = true

    @State private var images: HeroImages?

    var body: some View {
        let pose = moving ? HeroMotion.pose(at: time, pokedAt: pokedAt) : .rest
        GeometryReader { proxy in
            let size = proxy.size
            let cat = min(size.height, size.width * 4 / 3)
            ZStack {
                RadialGradient(colors: [Color.honey.opacity(0.42), Color.honeyDeep.opacity(0.14), .clear],
                               center: .center, startRadius: 0, endRadius: cat * 0.5)
                    .frame(width: cat * 1.1, height: cat * 1.1)
                    .scaleEffect(1 + 0.04 * pose.breath)
                    .offset(x: -8 * pose.sway, y: -cat * 0.06)
                DustField(time: moving ? time : 0, count: 16, reach: cat * 0.012)
                    .offset(x: 10 * pose.sway)
                Ellipse()
                    .fill(.black.opacity(0.42))
                    .frame(width: cat * 0.42, height: cat * 0.05)
                    .blur(radius: cat * 0.022)
                    .scaleEffect(1 - 0.12 * pose.hop)
                    .offset(x: 3 * pose.sway, y: cat * 0.43)
                if let images {
                    HeroCat(images: images, blink: pose.blink, ear: pose.ear)
                        .equatable()
                        .frame(width: cat * 3 / 4, height: cat)
                        .scaleEffect(x: 1 + 0.006 * pose.breath, y: 1 + 0.014 * pose.breath, anchor: .bottom)
                        .offset(x: 3 * pose.sway, y: -cat * 0.05 * pose.hop)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .animation(Motion.fade(Motion.standard), value: images == nil)
        .task(id: coat) { images = await HeroImages.load(coat) }
        .accessibilityHidden(true)
    }
}

/// The cat itself, drawn only when a frame changes: the rest image with the patches of the moment over it, a honey
/// halo, and a rim light on her upper-left edges where the warm light behind her catches the fur.
private struct HeroCat: View, Equatable {
    let images: HeroImages
    let blink: Int
    let ear: Int

    static func == (lhs: HeroCat, rhs: HeroCat) -> Bool {
        lhs.images.rest === rhs.images.rest && lhs.blink == rhs.blink && lhs.ear == rhs.ear
    }

    var body: some View {
        Canvas { context, size in
            let full = CGRect(origin: .zero, size: size)
            func scaled(_ rect: CGRect) -> CGRect {
                CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
                       width: rect.width * size.width, height: rect.height * size.height)
            }
            var patches: [(image: UIImage, rect: CGRect)] = []
            if blink > 0 { patches.append((images.blink[blink - 1], scaled(HeroImages.blinkRect))) }
            if ear > 0 { patches.append((images.ear[ear - 1], scaled(HeroImages.earRect))) }
            func cat(_ layer: inout GraphicsContext, offset: CGSize = .zero) {
                func moved(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: offset.width, dy: offset.height) }
                var rest = layer
                if !patches.isEmpty {
                    var cut = Path(moved(full))
                    for patch in patches { cut.addRect(moved(patch.rect)) }
                    rest.clip(to: cut, style: FillStyle(eoFill: true))
                }
                rest.draw(Image(uiImage: images.rest), in: moved(full))
                for patch in patches { layer.draw(Image(uiImage: patch.image), in: moved(patch.rect)) }
            }
            context.drawLayer { halo in
                halo.addFilter(.shadow(color: Color.honey.opacity(0.5), radius: size.width * 0.05))
                cat(&halo)
            }
            var lit = context
            lit.blendMode = .plusLighter
            lit.opacity = 0.55
            lit.drawLayer { rim in
                let edge = size.width * 0.012
                rim.addFilter(.blur(radius: edge * 0.6))
                rim.clipToLayer { mask in cat(&mask) }
                rim.fill(Path(full), with: .color(Color.honey))
                rim.blendMode = .destinationOut
                cat(&rim, offset: CGSize(width: edge, height: edge * 1.4))
            }
        }
    }
}

/// Specks of warm dust drifting up through the light, each with its own pace, sway and twinkle; fixed by `seed`, so
/// the same time draws the same field.
struct DustField: View {
    let time: TimeInterval
    var count = 18
    /// The largest speck's radius, in points.
    var reach: CGFloat = 4
    var seed: UInt64 = 7

    var body: some View {
        Canvas { context, size in
            var random = SeededRandom(seed: seed)
            func unit() -> Double { Double(random.next() >> 11) / Double(1 << 53) }
            for _ in 0..<count {
                let x = unit(), y = unit(), pace = 0.015 + 0.03 * unit()
                let phase = 2 * .pi * unit(), radius = reach * (0.35 + 0.65 * unit())
                let rise = (y - pace * time).truncatingRemainder(dividingBy: 1)
                let point = CGPoint(x: (x + 0.025 * sin(time * 0.6 + phase)) * size.width,
                                    y: (rise < 0 ? rise + 1 : rise) * size.height)
                let twinkle = 0.2 + 0.45 * (0.5 + 0.5 * sin(time * 1.3 + phase))
                let glow = CGRect(x: point.x, y: point.y, width: 0, height: 0).insetBy(dx: -radius * 3, dy: -radius * 3)
                context.fill(Path(ellipseIn: glow), with: .radialGradient(
                    Gradient(colors: [Color.honey.opacity(twinkle), Color.honey.opacity(0)]),
                    center: point, startRadius: 0, endRadius: radius * 3))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The warm room the onboarding pages sit in: the screen colour, a honey glow up top and dust drifting through it.
struct HeroBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        ZStack {
            Ink.screen
            RadialGradient(colors: [Color.honey.opacity(0.26), Color.honey.opacity(0.06), .clear],
                           center: UnitPoint(x: 0.5, y: 0.2), startRadius: 0, endRadius: 460)
            LinearGradient(colors: [.clear, Ink.surfaceRaised.opacity(0.9)], startPoint: .center, endPoint: .bottom)
            // Thirty frames a second is plenty for specks this slow, and leaves the main thread the other half.
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                DustField(time: reduceMotion ? 0 : context.date.timeIntervalSince(start), count: 12, reach: 3,
                          seed: 3)
                    .opacity(0.7)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#Preview {
    TimelineView(.animation) { context in
        CatHeroStage(coat: .grey, time: context.date.timeIntervalSinceReferenceDate)
            .frame(height: 360)
    }
    .background(HeroBackdrop())
}
