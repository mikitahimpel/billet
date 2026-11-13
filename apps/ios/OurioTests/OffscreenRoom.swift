import Metal
import RealityKit
import UIKit

@testable import Billet

/// A room drawn by a `RealityRenderer` into a texture of its own, for comparing two states of the same room pixel by pixel.
@MainActor
enum OffscreenRoom {
    static let width = 780
    static let height = 1688
    /// The camera of the last frame drawn, over a 390 x 844 point screen, as the room's own loop reads it for taps.
    nonisolated(unsafe) static var camera: RoomCamera?

    struct Difference {
        var maxError = 0
        var changed = 0
        var over8 = 0
        var total = 0
        var meanError = 0.0
        var share: Double { total == 0 ? 0 : Double(changed) / Double(total) }
        var shareOver8: Double { total == 0 ? 0 : Double(over8) / Double(total) }
        var line: String {
            "max channel error \(maxError)/255, mean \(String(format: "%.4f", meanError)), pixels off by >2: \(changed) of \(total) (\(String(format: "%.4f", share * 100)) %)"
        }
    }

    /// BGRA pixels of `room` seen from its default camera, after `frames` frames so lights, shadows and the image light settle.
    static func render(_ room: CatRoom, frames: Int = 10) async throws -> [UInt8] {
        let renderer = try RealityRenderer()
        renderer.cameraSettings.colorBackground = .color(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        renderer.cameraSettings.antialiasing = .none
        let rig = ZoomRig()
        rig.aspect = Float(width) / Float(height)
        rig.update(dt: 1, framing: room.framing, focusDistance: 0.8, yaw: 0, focus: [0.06, 0.12, -0.04], photo: nil)
        camera = RoomCamera(
            transform: rig.camera.transformMatrix(relativeTo: nil), fovDegrees: rig.camera.camera.fieldOfViewInDegrees,
            size: CGSize(width: width / 2, height: height / 2))
        renderer.entities.append(rig.camera)
        renderer.activeCamera = rig.camera
        renderer.entities.append(room.root)
        defer { renderer.entities.remove(room.root) }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = MTLCreateSystemDefaultDevice()?.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "OffscreenRoom", code: 1)
        }
        for _ in 0..<frames {
            let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                do {
                    try renderer.updateAndRender(deltaTime: 0.1, cameraOutput: output, onComplete: { _ in done.resume() })
                } catch {
                    done.resume()
                }
            }
            try await Task.sleep(for: .milliseconds(60))
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Difference {
        var d = Difference()
        d.total = min(a.count, b.count) / 4
        var sum = 0
        for p in 0..<d.total {
            var worst = 0
            for c in 0..<3 {
                let e = abs(Int(a[p * 4 + c]) - Int(b[p * 4 + c]))
                worst = max(worst, e)
                sum += e
            }
            d.maxError = max(d.maxError, worst)
            if worst > 2 { d.changed += 1 }
            if worst > 8 { d.over8 += 1 }
        }
        d.meanError = Double(sum) / Double(max(d.total * 3, 1))
        return d
    }

    /// Share of pixels that differ from the grey background: proof the picture is a room and not an empty frame.
    static func covered(_ pixels: [UInt8]) -> Double {
        var n = 0
        for p in 0..<(pixels.count / 4) where abs(Int(pixels[p * 4]) - 128) > 3 || abs(Int(pixels[p * 4 + 1]) - 128) > 3 { n += 1 }
        return Double(n) / Double(pixels.count / 4)
    }

    static func write(_ pixels: [UInt8], named name: String) {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"].map { $0 + "/Library/Caches/perf-scene-diet-dd/shots" } ?? NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var bytes = pixels
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: info),
            let image = context.makeImage(), let data = UIImage(cgImage: image).pngData()
        else { return }
        try? data.write(to: url.appending(path: name + ".png"))
        print("wrote \(url.appending(path: name + ".png").path)")
    }
}
