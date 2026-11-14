import Design
import ImageIO
import SwiftUI
import UIKit
import WidgetKit

/// Mochi as the app's hero bakes her (`Tools/bake_hero.py`): seated, at rest, in her coat, on transparency, 3:4. The
/// widgets stand her on their floor with the light the app's stage gives her, a honey glow behind and a contact
/// shadow under her paws, both gradients: a blur in a widget is drawn again for every entry. A tinted Home Screen
/// draws everything in one tint, so there she keeps her shape, desaturated, and no light of her own.
struct CatFigure: View {
    /// The snapshot's avatar name, `MochiPortrait` or `MochiPortrait-<coat>`, which names her coat.
    let avatar: String
    var asleep = false
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        Group {
            if let image = HeroFigure.image(for: avatar) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .widgetAccentedRenderingMode(.desaturated)
                    .scaledToFit()
                    .background { if mode == .fullColor { light } }
            } else {
                Image(systemName: "cat.fill").resizable().scaledToFit().foregroundStyle(Ink.textSecondary)
            }
        }
        .opacity(asleep ? 0.85 : 1)
        .accessibilityHidden(true)
    }

    /// The glow sits a little above her middle. The shadow is a flat ellipse the width of her haunches, its centre a
    /// hair under her paws, which the bake leaves at 92% of the image's height.
    private var light: some View {
        ZStack(alignment: .bottom) {
            EllipticalGradient(
                colors: [Color.honey.opacity(0.34), Color.honey.opacity(0.1), .clear],
                center: UnitPoint(x: 0.5, y: 0.44), startRadiusFraction: 0, endRadiusFraction: 0.5)
            EllipticalGradient(
                colors: [Color.honeyDeep.opacity(0.4), Color.honeyDeep.opacity(0.14), .clear],
                center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                .aspectRatio(6, contentMode: .fit)
                .scaleEffect(x: 0.72)
        }
    }
}

/// The hero at rest, read from the bundle once per coat and downsampled: an extension has little memory, and a
/// widget shows at most a few hundred points of her.
enum HeroFigure {
    /// The longer side after downsampling: the largest widget's stage at 3x.
    static let maxPixels = 720

    private static let cache = Cache()

    /// The coat an avatar name carries: `MochiPortrait` is the grey tabby, `MochiPortrait-<coat>` the others.
    static func coat(forAvatar avatar: String) -> String {
        let prefix = "MochiPortrait-"
        guard avatar.hasPrefix(prefix), avatar.count > prefix.count else { return "grey" }
        return String(avatar.dropFirst(prefix.count))
    }

    static func name(forAvatar avatar: String) -> String { "Hero-\(coat(forAvatar: avatar))" }

    /// Her coat's hero, or the grey tabby's when the bundle has no such coat.
    static func image(for avatar: String, in bundle: Bundle = .main) -> UIImage? {
        read(name(forAvatar: avatar), in: bundle) ?? read("Hero-grey", in: bundle)
    }

    private static func read(_ name: String, in bundle: Bundle) -> UIImage? {
        let key = "\(bundle.bundleURL.path)/\(name)" as NSString
        if let hit = cache.store.object(forKey: key) { return hit }
        guard let url = bundle.url(forResource: name, withExtension: "webp"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.store.setObject(image, forKey: key)
        return image
    }

    /// NSCache is thread-safe; the class only lets it be a static.
    private final class Cache: @unchecked Sendable {
        let store = NSCache<NSString, UIImage>()
    }
}
