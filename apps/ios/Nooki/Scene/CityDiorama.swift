import CoreGraphics

/// What the Bedroom's window shows as images: the numbers `Resources/CityDiorama/diorama.json` gives, and the
/// arithmetic that puts them in the window, kept apart from the layers so tests can reach it.
enum CityDiorama {
    static let times = ["day", "dusk", "night"]
    static let size = CGSize(width: 1280, height: 704)
    /// The part of each image the window shows; the rest is margin for the parallax.
    static let margin: CGFloat = 0.0556

    /// Parallax follow of each layer, far to near (the sky stays put).
    static let layers: [(name: String, follow: CGFloat)] = [
        ("sky", 0), ("far", 0.2), ("mid", 0.42), ("street", 0.62),
    ]

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

    /// The opacity of each of the stacked images, bottom first, that cross-fades them by `weights`.
    static func opacities(_ weights: [Float]) -> [Float] {
        var total: Float = 0
        return weights.map { weight in
            total += weight
            return total > 0 ? weight / total : 0
        }
    }

    /// The street, in the picture's own fractions: cars drive at a lane's height; the far lane goes left, the near one
    /// right; each stands before the edge of the crossing it reaches first.
    static let cars = (cells: 6, farScale: CGFloat(0.7059), nearScale: CGFloat(0.7792))
    static let crossing = (left: Float(0.5627), right: Float(0.7118))

    static let plan: CityTraffic.Plan = {
        let far = Float(cars.farScale) / Float(cars.cells), near = Float(cars.nearScale) / Float(cars.cells)
        return CityTraffic.Plan(
            lanes: [
                .init(y: 0.7604, direction: -1, stop: crossing.right + far / 2 + 0.01),
                .init(y: 0.793, direction: 1, stop: crossing.left - near / 2 - 0.01),
            ],
            span: -0.12...1.12, speeds: 0.025...0.04, waits: 8...16, gap: 0.25, capacity: 2, colours: cars.cells,
            holds: 3...5, pace: 0.02)
    }()
}
