import Compression
import Foundation

/// Niantic's .spz splat format, version 2 with SH degree 0, as Tools/ply_to_spz.py writes it: a gzip stream holding
/// a 16-byte header, then per splat 24-bit fixed-point positions, then alphas, colors, log scales and rotations,
/// a byte each.
nonisolated enum Spz {
    private static let magic: UInt32 = 0x5053_474E
    private static let colorScale: Float = 0.15

    /// The gzip member's deflate body, inflated to the size its trailer gives.
    static func gunzip(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 {
            guard offset + 2 <= bytes.count else { return nil }
            offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
        }
        for bit: UInt8 in [0x08, 0x10] where flags & bit != 0 {
            guard let zero = bytes[offset...].firstIndex(of: 0) else { return nil }
            offset = zero + 1
        }
        if flags & 0x02 != 0 { offset += 2 }
        let trailer = bytes.count - 4
        let size = Int(bytes[trailer]) | Int(bytes[trailer + 1]) << 8 | Int(bytes[trailer + 2]) << 16
            | Int(bytes[trailer + 3]) << 24
        guard offset < bytes.count - 8, size > 16 else { return nil }
        var output = [UInt8](repeating: 0, count: size)
        let written = bytes.withUnsafeBufferPointer { source in
            compression_decode_buffer(&output, size, source.baseAddress! + offset, bytes.count - 8 - offset, nil,
                                      COMPRESSION_ZLIB)
        }
        return written == size ? Data(output) : nil
    }

    /// The splats in GaussianSplatResource's layout, 14 floats each: position, log scale, rotation (w first),
    /// logit opacity, SH DC color.
    static func unpack(_ raw: Data) -> Data? {
        let bytes = [UInt8](raw)
        func u32(_ at: Int) -> UInt32 {
            UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        }
        guard bytes.count >= 16, u32(0) == magic, u32(4) == 2, bytes[12] == 0 else { return nil }
        let count = Int(u32(8))
        let fractional = Float(1 << Int(bytes[13]))
        guard bytes.count == 16 + count * 19 else { return nil }
        let positions = 16, alphas = positions + 9 * count, colors = alphas + count
        let scales = colors + 3 * count, rotations = scales + 3 * count

        var out = [Float](repeating: 0, count: 14 * count)
        for i in 0..<count {
            let o = 14 * i
            for k in 0..<3 {
                let p = positions + 9 * i + 3 * k
                var fixed = Int32(bytes[p]) | Int32(bytes[p + 1]) << 8 | Int32(bytes[p + 2]) << 16
                if fixed & 0x80_0000 != 0 { fixed |= ~0xFF_FFFF }
                out[o + k] = Float(fixed) / fractional
                out[o + 3 + k] = Float(bytes[scales + 3 * i + k]) / 16 - 10
                out[o + 11 + k] = (Float(bytes[colors + 3 * i + k]) / 255 - 0.5) / colorScale
            }
            let x = Float(bytes[rotations + 3 * i]) / 127.5 - 1
            let y = Float(bytes[rotations + 3 * i + 1]) / 127.5 - 1
            let z = Float(bytes[rotations + 3 * i + 2]) / 127.5 - 1
            out[o + 6] = (1 - min(1, x * x + y * y + z * z)).squareRoot()
            (out[o + 7], out[o + 8], out[o + 9]) = (x, y, z)
            // Half a step in from 0 and 1, so a fully clear or opaque splat keeps a finite logit.
            let alpha = (Float(bytes[alphas + i]) + 0.5) / 256
            out[o + 10] = log(alpha / (1 - alpha))
        }
        return out.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
