import Foundation
import MomentsInterface
import OurioShared
import UIKit
import UsInterface
import simd

/// Time of day: a palette keyed by hour, and the sun's and moon's directions. The window faces -Z (south, say):
/// the sun rises on the left (-X), stands high in front at noon and sets on the right.
nonisolated enum Daylight {
    /// Colors are sRGB components in 0...1.
    nonisolated struct Sample {
        var hour: Float = 12
        var top: SIMD3<Float> = .zero
        var horizon: SIMD3<Float> = .zero
        var sun: SIMD3<Float> = .zero
        var backdrop: SIMD3<Float> = .zero
        var sunIntensity: Float = 0
        /// How strong the ambient light is, 0.22 at night to 0.85 at noon.
        var env: Float = 0
        /// Drives everything people switch on: lamps, lit windows, street lights.
        var darkness: Float = 0
        var sunDirection: SIMD3<Float> = [0, 1, 0]
        var moonDirection: SIMD3<Float> = [0, -1, 0]
        /// Whichever of sun and moon is up, and its strength, fading out near the horizon.
        var lightDirection: SIMD3<Float> = [0, 1, 0]
        var lightIntensity: Float = 0
    }

    private nonisolated struct Key {
        let hour: Float
        let top, horizon, sun: UInt32
        let sunIntensity, env, darkness: Float
        let backdrop: UInt32
    }

    private static let keys: [Key] = [
        Key(hour: 0, top: 0x070B1E, horizon: 0x1A1F45, sun: 0x8EA4FF, sunIntensity: 0.35, env: 0.22, darkness: 1, backdrop: 0x2B1A12),
        Key(hour: 5, top: 0x0B1230, horizon: 0x2A2C58, sun: 0x8EA4FF, sunIntensity: 0.3, env: 0.25, darkness: 1, backdrop: 0x2B1A12),
        Key(hour: 6.3, top: 0x33427A, horizon: 0xF29A7A, sun: 0xFF9F6E, sunIntensity: 0.9, env: 0.42, darkness: 0.65, backdrop: 0x6D4B4A),
        Key(hour: 7.6, top: 0x6AA5DF, horizon: 0xFFD7B0, sun: 0xFFD9B5, sunIntensity: 2.2, env: 0.7, darkness: 0.15, backdrop: 0xE9D7C4),
        Key(hour: 12, top: 0x4C97E6, horizon: 0xCDE5FF, sun: 0xFFF6EA, sunIntensity: 3, env: 0.85, darkness: 0, backdrop: 0xF3E3CC),
        Key(hour: 16.8, top: 0x5590D4, horizon: 0xFFE3BD, sun: 0xFFE4BD, sunIntensity: 2.6, env: 0.8, darkness: 0.05, backdrop: 0xF1DCC2),
        Key(hour: 18.8, top: 0x3C4D8C, horizon: 0xFF9459, sun: 0xFF8A48, sunIntensity: 1.5, env: 0.55, darkness: 0.5, backdrop: 0xB9714A),
        Key(hour: 20.2, top: 0x151A40, horizon: 0x6A4170, sun: 0xA0A6FF, sunIntensity: 0.5, env: 0.3, darkness: 0.9, backdrop: 0x4A2A1C),
        Key(hour: 22, top: 0x070B1E, horizon: 0x1A1F45, sun: 0x8EA4FF, sunIntensity: 0.35, env: 0.22, darkness: 1, backdrop: 0x2B1A12),
    ]

    private static let sunrise: Float = 6.3
    private static let sunset: Float = 19.3

    /// The palette at an hour in [0, 24), blended between the two nearest keys.
    static func sample(_ hour: Float) -> Sample {
        let h = (hour.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
        var i = (keys.firstIndex { $0.hour > h } ?? 0) - 1
        if i < 0 { i = keys.count - 2 }
        let a = keys[i], b = keys[i + 1]
        let t = smoothstep(h, a.hour, b.hour)
        func mix(_ x: UInt32, _ y: UInt32) -> SIMD3<Float> { simd_mix(rgb(x), rgb(y), SIMD3(repeating: t)) }
        func mix(_ x: Float, _ y: Float) -> Float { x + (y - x) * t }

        var s = Sample()
        s.hour = h
        s.top = mix(a.top, b.top)
        s.horizon = mix(a.horizon, b.horizon)
        s.sun = mix(a.sun, b.sun)
        s.backdrop = mix(a.backdrop, b.backdrop)
        s.sunIntensity = mix(a.sunIntensity, b.sunIntensity)
        s.env = mix(a.env, b.env)
        s.darkness = mix(a.darkness, b.darkness)
        s.sunDirection = arc((h - sunrise + 24).truncatingRemainder(dividingBy: 24), span: sunset - sunrise)
        s.moonDirection = arc((h - sunset + 24).truncatingRemainder(dividingBy: 24), span: 24 - sunset + sunrise)
        s.lightDirection = s.sunDirection.y > 0 ? s.sunDirection : s.moonDirection
        s.lightIntensity = s.sunIntensity * smoothstep(s.lightDirection.y, 0, 0.12)
        return s
    }

    /// With minutes.
    static func localHour(_ date: Date = .now) -> Float {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return Float(c.hour ?? 12) + Float(c.minute ?? 0) / 60 + Float(c.second ?? 0) / 3600
    }

    static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF), Float((hex >> 8) & 0xFF), Float(hex & 0xFF)) / 255
    }

    static func color(_ c: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    /// Direction of a body `hours` after it rose on the left; it sets on the right after `span` hours.
    private static func arc(_ hours: Float, span: Float) -> SIMD3<Float> {
        let a = min(hours, span + 1) / span * .pi
        return simd_normalize([-cos(a), 0.8 * sin(a), -0.55 - 0.25 * max(sin(a), 0)])
    }
}

nonisolated func smoothstep(_ x: Float, _ low: Float, _ high: Float) -> Float {
    let u = min(max((x - low) / (high - low), 0), 1)
    return u * u * (3 - 2 * u)
}
