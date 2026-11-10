import Design
import SwiftUI
import UIKit

/// The hero Mochi's pictures for one coat as they ship, from `Tools/bake_hero.py`: her splat sitting at rest, 3:4, and
/// the patches that close her lids and flick her ear. A patch replaces its rectangle of the rest image; outside it the
/// frames are the rest image, pixel for pixel.
nonisolated struct HeroArt: @unchecked Sendable {
    let rest: UIImage
    /// Half and fully shut.
    let blink: [UIImage]
    /// Half and fully out.
    let ear: [UIImage]

    /// The patches' rectangles as fractions of the rest image, printed by the bake.
    static let blinkRect = CGRect(x: 0.33796, y: 0.20208, width: 0.40741, height: 0.20556)
    static let earRect = CGRect(x: 0.25926, y: 0.11111, width: 0.18889, height: 0.15764)

    /// Reads and decodes; it blocks, so it runs off the main actor.
    static func read(_ coat: CatCoat, from bundle: Bundle) -> HeroArt? {
        let names = ["Hero", "HeroBlink1", "HeroBlink2", "HeroEar1", "HeroEar2"]
        let images = names.compactMap { name in
            bundle.url(forResource: "\(name)-\(coat.rawValue)", withExtension: "webp")
                .flatMap { UIImage(contentsOfFile: $0.path)?.preparingForDisplay() }
        }
        guard images.count == names.count else { return nil }
        return HeroArt(rest: images[0], blink: Array(images[1...2]), ear: Array(images[3...4]))
    }

    /// The whole cat with `blink` and `ear` frames (0 rest) laid over the rest image.
    func frame(blink: Int, ear: Int) -> UIImage {
        let size = rest.size
        func pixels(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
                   width: rect.width * size.width, height: rect.height * size.height).integral
        }
        var patches: [(image: UIImage, rect: CGRect)] = []
        if blink > 0 { patches.append((self.blink[blink - 1], pixels(Self.blinkRect))) }
        if ear > 0 { patches.append((self.ear[ear - 1], pixels(Self.earRect))) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let full = CGRect(origin: .zero, size: size)
            context.cgContext.saveGState()
            if !patches.isEmpty {
                let cut = CGMutablePath()
                cut.addRect(full)
                for patch in patches { cut.addRect(patch.rect) }
                context.cgContext.addPath(cut)
                context.cgContext.clip(using: .evenOdd)
            }
            rest.draw(in: full)
            context.cgContext.restoreGState()
            for patch in patches { patch.image.draw(in: patch.rect) }
        }
    }
}

/// The hero Mochi lit for the stage: a honey halo around her and a rim of warm light on her upper-left edges, baked
/// once into each frame off the main actor, so the stage draws plain images and never runs a blur or a shadow while
/// it plays.
nonisolated struct HeroImages: @unchecked Sendable {
    /// Her ear at rest, half and fully out.
    let lit: [UIImage]
    /// `blinks[ear][n]`: lids half (0) and fully (1) shut with the ear in that frame, cut to `HeroArt.blinkRect`.
    let blinks: [[UIImage]]

    static func load(_ coat: CatCoat, tint: Color.Resolved, from bundle: Bundle = .main) async -> HeroImages? {
        await Task.detached(priority: .userInitiated) { () -> HeroImages? in
            HeroArt.read(coat, from: bundle).flatMap { lighting($0, tint: tint) }
        }.value
    }

    static func lighting(_ art: HeroArt, tint: Color.Resolved) -> HeroImages? {
        let context = CIContext(options: [.cacheIntermediates: false])
        let colour = tint.cgColor
        func render(blink: Int, ear: Int, cutTo fraction: CGRect? = nil) -> UIImage? {
            guard let cat = CIImage(image: art.frame(blink: blink, ear: ear)) else { return nil }
            let extent = cat.extent
            // Core Image counts y from the bottom.
            let crop = fraction.map {
                CGRect(x: $0.minX * extent.width, y: (1 - $0.maxY) * extent.height,
                       width: $0.width * extent.width, height: $0.height * extent.height).integral
            } ?? extent
            guard let image = context.createCGImage(Self.lighting(cat, colour: colour), from: crop) else { return nil }
            return UIImage(cgImage: image)
        }
        let lit = (0...2).compactMap { render(blink: 0, ear: $0) }
        let blinks = (0...2).map { ear in
            (1...2).compactMap { render(blink: $0, ear: ear, cutTo: HeroArt.blinkRect) }
        }
        guard lit.count == 3, blinks.allSatisfy({ $0.count == 2 }) else { return nil }
        return HeroImages(lit: lit, blinks: blinks)
    }

    /// The halo is her silhouette in honey at half strength, blurred by 5% of her width, under her. The rim is her
    /// silhouette less itself moved down and right by 1.2% of her width, softened and added at 0.55: light from
    /// behind, upper left, catching her edge.
    private static func lighting(_ cat: CIImage, colour: CGColor) -> CIImage {
        let extent = cat.extent
        func silhouette(_ alpha: CGFloat) -> CIImage {
            CIImage(color: CIColor(cgColor: colour.copy(alpha: alpha) ?? colour))
                .cropped(to: extent)
                .applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: cat])
        }
        let halo = silhouette(0.5).clampedToExtent().applyingGaussianBlur(sigma: extent.width * 0.025)
            .cropped(to: extent)
        let edge = extent.width * 0.012
        let moved = cat.transformed(by: CGAffineTransform(translationX: edge, y: -edge * 1.4))
        let strength = 0.55
        let rim = silhouette(1)
            .applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: moved])
            .clampedToExtent()
            .applyingGaussianBlur(sigma: edge * 0.3)
            .cropped(to: extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: strength, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: strength, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: strength, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: strength),
            ])
        return rim.applyingFilter("CIAdditionCompositing",
                                  parameters: [kCIInputBackgroundImageKey: cat.composited(over: halo)])
    }
}

/// Mochi on a warm stage: a glow behind her, drifting dust, a contact shadow, and the loop of `HeroMotion` (breath,
/// sway, blinks, an ear flick, a hop on `pokedAt`). The parent's clock drives it; with `moving` false she rests and
/// nothing drifts. Each layer sways by its own amount, for depth. Nothing here blurs or shadows per frame: the light on
/// her is baked into `HeroImages`, and the contact shadow is a gradient.
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
                DustField(time: moving ? time : 0, count: 12, reach: cat * 0.012)
                    .offset(x: 10 * pose.sway)
                EllipticalGradient(colors: [.black.opacity(0.42), .black.opacity(0.2), .clear],
                                   center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                    .frame(width: cat * 0.5, height: cat * 0.09)
                    .scaleEffect(1 - 0.12 * pose.hop)
                    .offset(x: 3 * pose.sway, y: cat * 0.43)
                if let images {
                    HeroCat(images: images, blink: pose.blink, ear: pose.ear,
                            size: CGSize(width: cat * 3 / 4, height: cat))
                        .equatable()
                        .scaleEffect(x: 1 + 0.006 * pose.breath, y: 1 + 0.014 * pose.breath, anchor: .bottom)
                        .offset(x: 3 * pose.sway, y: -cat * 0.05 * pose.hop)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .animation(Motion.fade(Motion.standard), value: images == nil)
        .task(id: coat) {
            images = await HeroImages.load(coat, tint: Color.honey.resolve(in: EnvironmentValues()))
        }
        .accessibilityHidden(true)
    }
}

/// The lit cat of the moment: her ear frame whole, and while she blinks, the lids of that ear frame over their
/// rectangle, which is cut out of the image under them so the two never add up.
private struct HeroCat: View, Equatable {
    let images: HeroImages
    let blink: Int
    let ear: Int
    let size: CGSize

    static func == (lhs: HeroCat, rhs: HeroCat) -> Bool {
        lhs.images.lit[0] === rhs.images.lit[0] && lhs.blink == rhs.blink && lhs.ear == rhs.ear
            && lhs.size == rhs.size
    }

    var body: some View {
        let lids = CGRect(x: HeroArt.blinkRect.minX * size.width, y: HeroArt.blinkRect.minY * size.height,
                          width: HeroArt.blinkRect.width * size.width, height: HeroArt.blinkRect.height * size.height)
        ZStack(alignment: .topLeading) {
            Image(uiImage: images.lit[ear])
                .resizable()
                .mask {
                    if blink > 0 {
                        Path { path in
                            path.addRect(CGRect(origin: .zero, size: size))
                            path.addRect(lids)
                        }
                        .fill(style: FillStyle(eoFill: true))
                    } else {
                        Rectangle()
                    }
                }
            if blink > 0 {
                Image(uiImage: images.blinks[ear][blink - 1])
                    .resizable()
                    .frame(width: lids.width, height: lids.height)
                    .offset(x: lids.minX, y: lids.minY)
            }
        }
        .frame(width: size.width, height: size.height)
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

    @State private var size = CGSize.zero

    private nonisolated struct Speck: Sendable {
        let x, y, pace, phase: Double
        let radius: CGFloat
    }

    private var specks: [Speck] {
        var random = SeededRandom(seed: seed)
        func unit() -> Double { Double(random.next() >> 11) / Double(1 << 53) }
        return (0..<count).map { _ in
            Speck(x: unit(), y: unit(), pace: 0.015 + 0.03 * unit(), phase: 2 * .pi * unit(),
                  radius: reach * (0.35 + 0.65 * unit()))
        }
    }

    /// One soft honey speck, drawn once. Each speck is a view of it that only moves and fades, so a frame of dust
    /// moves layers and draws nothing.
    private static let glow: UIImage = {
        let side: CGFloat = 48
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let honey = UIColor(Color.honey)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let colours = [honey.cgColor, honey.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours,
                                            locations: [0, 1]) else { return }
            let centre = CGPoint(x: side / 2, y: side / 2)
            context.cgContext.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre,
                                                 endRadius: side / 2, options: [])
        }
    }()

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(specks.enumerated()), id: \.offset) { _, speck in
                let rise = (speck.y - speck.pace * time).truncatingRemainder(dividingBy: 1)
                let reach = speck.radius * 3
                Image(uiImage: Self.glow)
                    .resizable()
                    .frame(width: reach * 2, height: reach * 2)
                    .opacity(0.2 + 0.45 * (0.5 + 0.5 * sin(time * 1.3 + speck.phase)))
                    .offset(x: (speck.x + 0.025 * sin(time * 0.6 + speck.phase)) * size.width - reach,
                            y: (rise < 0 ? rise + 1 : rise) * size.height - reach)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
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
