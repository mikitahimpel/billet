import CoreGraphics
import simd
import Foundation

/// What the Bedroom's window shows as images: the numbers `Resources/CityDiorama/diorama.json` gives, and the
/// arithmetic that puts them in the window, kept apart from the layers so tests can reach it.
enum CityDiorama {
    static let times = ["day", "dusk", "night"]
    static let size = CGSize(width: 1280, height: 704)
    /// The part of each image the window shows; the rest is margin for the parallax.
    static let margin: CGFloat = 0.0556

    /// What `Resources/CityDiorama/diorama.json` says, so a new bake of the street needs no code change; the defaults
    /// are the last bake's values for when the file cannot be read.
    private struct Config: Decodable {
        struct Layer: Decodable { let name: String; let follow: CGFloat }
        struct Lane: Decodable { let y: Float; let scale: CGFloat; let direction: Float }
        struct Crossing: Decodable { let left: Float; let right: Float }
        struct Cars: Decodable { let cells: Int; let lanes: [Lane]; let crossing: Crossing }
        let layers: [Layer]
        let cars: Cars

        static let current: Config = {
            guard let url = Bundle.main.url(forResource: "diorama", withExtension: "json", subdirectory: "CityDiorama")
                ?? Bundle.main.url(forResource: "diorama", withExtension: "json"),
                let data = try? Data(contentsOf: url),
                let config = try? JSONDecoder().decode(Config.self, from: data)
            else {
                return Config(
                    layers: [.init(name: "sky", follow: 0), .init(name: "far", follow: 0.2),
                             .init(name: "mid", follow: 0.42), .init(name: "street", follow: 0.62)],
                    cars: .init(cells: 6,
                                lanes: [.init(y: 0.838, scale: 1.1321, direction: -1),
                                        .init(y: 0.9076, scale: 1.3333, direction: 1)],
                                crossing: .init(left: 0.4748, right: 0.7138)))
            }
            return config
        }()
    }

    /// Parallax follow of each layer, far to near (the sky stays put). The cars are drawn above `street`; a layer named
    /// `near` goes in front of them.
    static let layers: [(name: String, follow: CGFloat)] = Config.current.layers.map { ($0.name, $0.follow) }

    /// The window's height in stage units, the width being 100.
    static let stageHeight: CGFloat = 58

    /// Where an image sits in stage units: its visible part covers the window, centred across it.
    static let imageRect: CGRect = {
        let visibleHeight = size.height * (1 - 2 * margin)
        let scale = stageHeight / visibleHeight
        let visibleWidth = size.width * (1 - 2 * margin) * scale
        let x = (100 - visibleWidth) / 2 - size.width * margin * scale
        let y = -size.height * margin * scale
        return CGRect(x: x, y: y, width: size.width * scale, height: size.height * scale)
    }()

    /// How much of day, dusk and night is on show at `hour`; they sum to one and only neighbours mix.
    static func weights(hour: Float) -> [Float] {
        let h = hour.truncatingRemainder(dividingBy: 24) + (hour < 0 ? 24 : 0)
        func ramp(_ from: Float, _ to: Float) -> Float { min(max((h - from) / (to - from), 0), 1) }
        switch h {
        case ..<5: return [0, 0, 1]
        case ..<7: let t = ramp(5, 7); return [0, t, 1 - t]
        case ..<8.5: let t = ramp(7, 8.5); return [t, 1 - t, 0]
        case ..<17: return [1, 0, 0]
        case ..<19: let t = ramp(17, 19); return [1 - t, t, 0]
        case ..<21: let t = ramp(19, 21); return [0, 1 - t, t]
        default: return [0, 0, 1]
        }
    }

    /// The sky the window is backed with, top and horizon: clear blue by day, warm at dusk, deep plum at night. It fills
    /// the whole opening, so no turn of the room ever shows what is behind the window.
    static let skies: [(top: SIMD3<Float>, horizon: SIMD3<Float>)] = [
        (rgb(0x4F9BE8), rgb(0xBFE1FF)), (rgb(0x4B4A86), rgb(0xFFB27A)), (rgb(0x1A1030), rgb(0x3B2346)),
    ]

    static func sky(hour: Float) -> (top: SIMD3<Float>, horizon: SIMD3<Float>) {
        let w = weights(hour: hour)
        var top = SIMD3<Float>.zero, horizon = SIMD3<Float>.zero
        for index in skies.indices {
            top += skies[index].top * w[index]
            horizon += skies[index].horizon * w[index]
        }
        return (top, horizon)
    }

    private static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF), Float((hex >> 8) & 0xFF), Float(hex & 0xFF)) / 255
    }

    /// The opacity of each of the stacked images, bottom first, that cross-fades them by `weights`.
    static func opacities(_ weights: [Float]) -> [Float] {
        var total: Float = 0
        return weights.map { weight in
            total += weight
            return total > 0 ? weight / total : 0
        }
    }

    /// The street, in the picture's own fractions: cars drive at a lane's height; the first lane goes left, the second
    /// right; each stands before the edge of the crossing it reaches first.
    static let cars = (cells: Config.current.cars.cells, scales: Config.current.cars.lanes.map(\.scale))
    static let crossing = (left: Config.current.cars.crossing.left, right: Config.current.cars.crossing.right)

    static let plan: CityTraffic.Plan = {
        let lanes = Config.current.cars.lanes
        let widths = lanes.map { Float($0.scale) / Float(cars.cells) }
        return CityTraffic.Plan(
            lanes: lanes.indices.map { index in
                let lane = lanes[index]
                let before = lane.direction < 0 ? crossing.right + widths[index] / 2 + 0.01
                    : crossing.left - widths[index] / 2 - 0.01
                return .init(y: lane.y, direction: lane.direction, stop: before)
            },
            span: -0.2...1.2, speeds: 0.025...0.04, waits: 8...16, gap: (widths.max() ?? 0.2) * 1.5, capacity: 2,
            colours: cars.cells, holds: 3...5, pace: 0.02)
    }()
}
