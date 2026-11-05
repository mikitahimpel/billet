import CoreGraphics
import Foundation

/// BlurHash (blurha.sh): a photo as a few dozen characters the partner's phone can paint as a soft blur while the
/// photo itself loads. Safe off the main thread.
nonisolated enum BlurHash {
    /// The hash of `image` with `x` by `y` components (1 to 9 each), from a 32 px copy of it.
    static func encode(_ image: CGImage, x: Int = 4, y: Int = 3) -> String? {
        guard (1...9).contains(x), (1...9).contains(y) else { return nil }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            // Nearest sampling: smoothing would blend the black outside the image into the border pixels.
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var factors: [(r: Double, g: Double, b: Double)] = []
        for j in 0..<y {
            for i in 0..<x {
                let normalisation: Double = i == 0 && j == 0 ? 1 : 2
                var r = 0.0, g = 0.0, b = 0.0
                for py in 0..<side {
                    let cosY = cos(Double.pi * Double(j) * Double(py) / Double(side))
                    for px in 0..<side {
                        let basis = cos(Double.pi * Double(i) * Double(px) / Double(side)) * cosY
                        let offset = (py * side + px) * 4
                        r += basis * linear(pixels[offset])
                        g += basis * linear(pixels[offset + 1])
                        b += basis * linear(pixels[offset + 2])
                    }
                }
                let scale = normalisation / Double(side * side)
                factors.append((r * scale, g * scale, b * scale))
            }
        }

        let dc = factors[0]
        let ac = factors.dropFirst()
        var hash = base83((x - 1) + (y - 1) * 9, length: 1)
        let maximum: Double
        if let largest = ac.map({ max(abs($0.r), abs($0.g), abs($0.b)) }).max() {
            let quantised = max(0, min(82, Int((largest * 166 - 0.5).rounded(.down))))
            maximum = Double(quantised + 1) / 166
            hash += base83(quantised, length: 1)
        } else {
            maximum = 1
            hash += base83(0, length: 1)
        }
        hash += base83((sRGB(dc.r) << 16) + (sRGB(dc.g) << 8) + sRGB(dc.b), length: 4)
        for factor in ac {
            func quantise(_ value: Double) -> Int {
                max(0, min(18, Int((signedPow(value / maximum, 0.5) * 9 + 9.5).rounded(.down))))
            }
            hash += base83(quantise(factor.r) * 19 * 19 + quantise(factor.g) * 19 + quantise(factor.b), length: 2)
        }
        return hash
    }

    private static let characters = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")

    private static func base83(_ value: Int, length: Int) -> String {
        var result = ""
        for digit in 1...length {
            var divisor = 1
            for _ in 0..<(length - digit) { divisor *= 83 }
            result.append(characters[(value / divisor) % 83])
        }
        return result
    }

    private static func linear(_ value: UInt8) -> Double {
        let v = Double(value) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func sRGB(_ value: Double) -> Int {
        let v = max(0, min(1, value))
        return v <= 0.0031308 ? Int(v * 12.92 * 255 + 0.5) : Int((1.055 * pow(v, 1 / 2.4) - 0.055) * 255 + 0.5)
    }

    private static func signedPow(_ value: Double, _ exponent: Double) -> Double {
        (value < 0 ? -1 : 1) * pow(abs(value), exponent)
    }
}
