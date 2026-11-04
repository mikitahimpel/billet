import UIKit
import simd

/// The view from the City room's window, painted flat for the time of day: sky with the sun or moon and stars, a far
/// skyline, a row of houses across the street whose windows light up in the evening, and a hedge along the pavement.
/// The layout is seeded, so the street is the same on every load; only its colors follow the light.
nonisolated enum TownPicture {
    static let size = CGSize(width: 1024, height: 560)

    private nonisolated struct Window {
        let rect: CGRect
        /// Darkness at which someone switches this one on.
        let threshold: Float
        let tone: SIMD3<Float>
    }

    private nonisolated struct House {
        let body: CGRect
        let roof: CGFloat
        let tone: SIMD3<Float>
        let roofTone: SIMD3<Float>
        let windows: [Window]
        let door: CGRect
    }

    private nonisolated struct Tower {
        let rect: CGRect
        let tone: SIMD3<Float>
        let windows: [Window]
    }

    private static let horizon: CGFloat = 0.6 * size.height
    private static let street: CGFloat = 0.84 * size.height
    private static let layout = makeLayout()

    /// The picture for `light`; safe to draw off the main thread.
    static func image(_ light: Daylight.Sample) -> UIImage {
        let darkness = light.darkness
        // Daylight on the walls, down to a dim blue at night.
        let shade = simd_mix(simd_mix(light.horizon, .one, SIMD3(repeating: 0.6)), Daylight.rgb(0x2A3550),
                             SIMD3(repeating: darkness * 0.85))
        func lit(_ tone: SIMD3<Float>) -> UIColor { Daylight.color(tone * shade) }
        let warm = Daylight.rgb(0xFFC777)
        let glass = simd_mix(simd_mix(light.top, light.horizon, SIMD3(repeating: 0.5)) * 0.6, Daylight.rgb(0x10141F),
                             SIMD3(repeating: darkness))
        func window(_ w: Window) -> UIColor {
            let on = smoothstep(darkness, w.threshold - 0.06, w.threshold + 0.06)
            return Daylight.color(simd_mix(glass, w.tone, SIMD3(repeating: on)))
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let w = size.width

            // Sky.
            let sky = [Daylight.color(light.top).cgColor, Daylight.color(light.horizon).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sky, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: street), options: [])
            }
            let stars = smoothstep(darkness, 0.6, 1)
            if stars > 0 {
                var random = Random(3)
                UIColor(white: 1, alpha: CGFloat(stars * 0.9)).setFill()
                for _ in 0 ..< 70 {
                    let x = CGFloat(random.next()) * w, y = CGFloat(random.next()) * horizon * 0.9
                    let r = 0.8 + CGFloat(random.next()) * 1.4
                    cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                }
            }
            for (direction, color, radius) in [(light.sunDirection, light.sun, CGFloat(30)),
                                               (light.moonDirection, Daylight.rgb(0xF4F1E6), CGFloat(20))]
                where direction.y > 0 {
                let x = (0.5 + 0.42 * CGFloat(direction.x)) * w
                let y = horizon - CGFloat(direction.y) * horizon * 0.85
                Daylight.color(color).setFill()
                cg.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
            }

            // The far skyline, hazy with the sky behind it.
            for tower in layout.towers {
                let haze = simd_mix(tower.tone * shade, light.horizon, SIMD3(repeating: 0.45))
                Daylight.color(haze).setFill()
                cg.fill(tower.rect)
                for pane in tower.windows {
                    window(pane).setFill()
                    cg.fill(pane.rect)
                }
            }

            // The houses across the street.
            for house in layout.houses {
                lit(house.tone).setFill()
                cg.fill(house.body)
                lit(house.roofTone).setFill()
                cg.move(to: CGPoint(x: house.body.minX - 8, y: house.body.minY))
                cg.addLine(to: CGPoint(x: house.body.midX, y: house.body.minY - house.roof))
                cg.addLine(to: CGPoint(x: house.body.maxX + 8, y: house.body.minY))
                cg.closePath()
                cg.fillPath()
                for pane in house.windows {
                    window(pane).setFill()
                    cg.fill(pane.rect)
                }
                lit(Daylight.rgb(0x6D4C3A)).setFill()
                cg.fill(house.door)
            }

            // Street lamps between the houses, glowing once it gets dark.
            let lamps = smoothstep(darkness, 0.2, 0.6)
            for x in layout.lamps {
                lit(Daylight.rgb(0x3B3A40)).setFill()
                cg.fill(CGRect(x: x - 2, y: street - 120, width: 4, height: 120))
                let glow = CGFloat(lamps)
                Daylight.color(simd_mix(Daylight.rgb(0xE8E1D2) * shade, warm, SIMD3(repeating: lamps))).setFill()
                cg.fillEllipse(in: CGRect(x: x - 7, y: street - 128, width: 14, height: 14))
                if glow > 0 {
                    UIColor(red: 1, green: 0.8, blue: 0.45, alpha: 0.25 * glow).setFill()
                    cg.fillEllipse(in: CGRect(x: x - 26, y: street - 147, width: 52, height: 52))
                }
            }

            // Pavement and the hedge along the near side.
            lit(Daylight.rgb(0xC9BCA9)).setFill()
            cg.fill(CGRect(x: 0, y: street, width: w, height: 18))
            lit(Daylight.rgb(0x6F8A4E)).setFill()
            cg.fill(CGRect(x: 0, y: street + 18, width: w, height: size.height - street - 18))
            lit(Daylight.rgb(0x7F9A5A)).setFill()
            var x: CGFloat = -10
            while x < w {
                cg.fillEllipse(in: CGRect(x: x, y: street + 4, width: 46, height: 34))
                x += 34
            }
        }
    }

    // MARK: - Layout

    private static func makeLayout() -> (towers: [Tower], houses: [House], lamps: [CGFloat]) {
        var random = Random(7)
        func pick<T>(_ list: [T]) -> T { list[min(Int(random.next() * Float(list.count)), list.count - 1)] }
        func pane(_ rect: CGRect, tv: Bool = false) -> Window {
            let tone = tv ? Daylight.rgb(0x8FB4FF) : pick([0xFFC777, 0xFFD9A0, 0xFFB868].map(Daylight.rgb))
            return Window(rect: rect, threshold: 0.3 + random.next() * 0.55, tone: tone)
        }

        var towers: [Tower] = []
        var x: CGFloat = -20
        while x < size.width {
            let w = 60 + CGFloat(random.next()) * 70
            let h = 50 + CGFloat(random.next()) * 110
            let rect = CGRect(x: x, y: horizon + 40 - h, width: w, height: h + 40)
            var panes: [Window] = []
            var y = rect.minY + 10
            while y < horizon + 20 {
                var px = rect.minX + 8
                while px + 6 < rect.maxX - 6 {
                    if random.next() < 0.35 { panes.append(pane(CGRect(x: px, y: y, width: 6, height: 8))) }
                    px += 14
                }
                y += 16
            }
            towers.append(Tower(rect: rect, tone: pick([0xA9B4C4, 0xB8B1B8, 0x9AA6B6, 0xC2B7AE].map(Daylight.rgb)),
                                windows: panes))
            x += w + 6 + CGFloat(random.next()) * 30
        }

        var houses: [House] = []
        var lamps: [CGFloat] = []
        x = -30
        while x < size.width {
            let w = 120 + CGFloat(random.next()) * 60
            let h = 100 + CGFloat(random.next()) * 50
            let body = CGRect(x: x, y: street - h, width: w, height: h)
            var panes: [Window] = []
            let floors = h > 125 ? 2 : 1
            for f in 0 ..< floors {
                for c in 0 ..< 2 {
                    let px = body.minX + w * (c == 0 ? 0.16 : 0.62)
                    let py = body.minY + 16 + CGFloat(f) * 48
                    panes.append(pane(CGRect(x: px, y: py, width: w * 0.22, height: 30), tv: random.next() < 0.12))
                }
            }
            let door = CGRect(x: body.midX - 13, y: street - 44, width: 26, height: 44)
            houses.append(House(body: body, roof: 40 + CGFloat(random.next()) * 30,
                                tone: pick([0xF1E4CC, 0xE9C9A8, 0xD9E1D2, 0xF3D9C6, 0xE6D3B3].map(Daylight.rgb)),
                                roofTone: pick([0x8C4A3A, 0x6F5149, 0xA35D46, 0x5D6470].map(Daylight.rgb)),
                                windows: panes, door: door))
            x += w + 26 + CGFloat(random.next()) * 30
            lamps.append(x - 13)
        }
        return (towers, houses, lamps)
    }

    /// Small seeded generator (the JS `mulberry32`), so the street is the same on every load.
    private nonisolated struct Random {
        private var seed: UInt32

        init(_ seed: UInt32) {
            self.seed = seed
        }

        mutating func next() -> Float {
            seed = seed &+ 0x6D2B79F5
            var t = (seed ^ (seed >> 15)) &* (1 | seed)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Float(t ^ (t >> 14)) / 4294967296
        }
    }
}
