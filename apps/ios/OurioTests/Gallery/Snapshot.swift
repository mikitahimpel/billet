import Design
import Foundation
import ImageIO
import SwiftUI
import Testing
import UIKit
import UniformTypeIdentifiers

/// Draws a view in a window the size of a phone at a fixed scale and compares it with its lossless
/// WebP reference in `packages/ios/design/Tests/Gallery/References`. A missing or different drawing is
/// written as a PNG to `Recorded/` beside them and fails; `scripts/gallery.sh --record` turns those into
/// the new references.
@MainActor
enum Snapshot {
    enum Variant: String, CaseIterable, Sendable {
        case se
        case proMax = "promax"
        case largestText = "se-ax5"

        var size: CGSize {
            switch self {
            case .se, .largestText: CGSize(width: 375, height: 667)
            case .proMax: CGSize(width: 440, height: 956)
            }
        }

        var dynamicType: DynamicTypeSize {
            switch self {
            case .se, .proMax: .large
            case .largestText: .accessibility5
            }
        }
    }

    /// A pixel counts as changed when a channel moves by more than this, out of 255.
    static let channelTolerance = 8
    /// The share of changed pixels a match allows: antialiasing, never a moved or resized view.
    static let pixelTolerance = 0.005
    static let scale: CGFloat = 2

    static let gallery = Repo.root.appending(path: "packages/ios/design/Tests/Gallery")
    static let references = gallery.appending(path: "References")
    static let recorded = gallery.appending(path: "Recorded")

    /// `fits` sizes the drawing to the view's height at the variant's width; otherwise it is the whole screen.
    static func render(_ view: some View, variant: Variant, fits: Bool) -> CGImage? {
        let root = view
            .environment(\.dynamicTypeSize, variant.dynamicType)
            .environment(\.colorScheme, .light)
        let controller = UIHostingController(rootView: root)
        controller.overrideUserInterfaceStyle = .light
        var size = variant.size
        if fits {
            controller.safeAreaRegions = []
            let height = controller.sizeThatFits(in: CGSize(width: size.width, height: .greatestFiniteMagnitude)).height
            size.height = ceil(height)
        }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        UIView.performWithoutAnimation {
            controller.view.frame = window.bounds
            controller.view.layoutIfNeeded()
        }
        // Lets `.task` and `onAppear` content, such as a list's first page, land before the drawing: the run loop
        // turns until two small drawings in a row agree, for 2 s at most (a spinner never settles).
        let deadline = Date.now + (fits ? 0.3 : 2)
        var last: Data?
        repeat {
            RunLoop.main.run(until: min(deadline, .now + 0.15))
            controller.view.layoutIfNeeded()
            let sketch = draw(controller.view, size: size, scale: 0.25).cgImage.flatMap(rgba).map { Data($0) }
            if sketch != nil, sketch == last { break }
            last = sketch
        } while Date.now < deadline
        return draw(controller.view, size: size, scale: scale).cgImage
    }

    private static func draw(_ view: UIView, size: CGSize, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
    }

    static func match(_ image: CGImage, name: String) throws {
        let reference = references.appending(path: "\(name).webp")
        guard let expected = load(reference) else {
            try write(image, to: recorded.appending(path: "\(name).png"))
            Issue.record("No reference for \(name); recorded one in packages/ios/design/Tests/Gallery/Recorded")
            return
        }
        let changed = difference(image, expected)
        if changed > pixelTolerance {
            try write(image, to: recorded.appending(path: "\(name).png"))
            Issue.record(
                "\(name) differs from its reference in \(String(format: "%.2f", changed * 100))% of pixels; the new drawing is in Recorded")
        }
    }

    /// The share of pixels that differ, or 1 when the sizes do.
    static func difference(_ a: CGImage, _ b: CGImage) -> Double {
        guard a.width == b.width, a.height == b.height, let left = rgba(a), let right = rgba(b) else { return 1 }
        if left == right { return 0 }
        // Raw pointers: the tests build unoptimised, where indexing the arrays costs seconds per drawing.
        let changed = left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                var changed = 0
                var pixel = 0
                while pixel < l.count {
                    var channel = 0
                    while channel < 4 {
                        let delta = Int(l[pixel + channel]) - Int(r[pixel + channel])
                        if delta > channelTolerance || delta < -channelTolerance {
                            changed += 1
                            break
                        }
                        channel += 1
                    }
                    pixel += 4
                }
                return changed
            }
        }
        return Double(changed) / Double(a.width * a.height)
    }

    static func rgba(_ image: CGImage) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? bytes : nil
    }

    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func write(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw SnapshotError.cannotWrite(url.lastPathComponent) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw SnapshotError.cannotWrite(url.lastPathComponent) }
    }
}

enum SnapshotError: Error {
    case cannotWrite(String)
}
