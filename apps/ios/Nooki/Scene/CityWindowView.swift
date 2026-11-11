import Pet
import simd
import UIKit
import WindowViews

/// The Bedroom's window: the street as clay image layers by default, and the flat painted views when Settings
/// asks for one of them or the weather is rain or snow. Told the same things as the flat view, it passes them on.
@MainActor
final class CityWindowView: UIView {
    private let flat = FlatWindowView()
    private let diorama = CityDioramaView()
    private var usesDiorama = true
    /// The sky behind whichever view is shown, clipped to the hole in the wall.
    private let backing = CAGradientLayer()
    private let backingClip = CAShapeLayer()
    private var skyHour: Float = -1
    private var placed: (window: [CGPoint], home: [CGPoint], hole: [CGPoint]) = ([], [], [])

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        backing.mask = backingClip
        backing.isHidden = true
        layer.addSublayer(backing)
        for view in [flat, diorama] as [UIView] {
            view.frame = bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var isReady: Bool { usesDiorama ? diorama.isReady : flat.isReady }

    func show(_ choice: WindowChoice, hour: Float, weather: ViewWeather, lampOn: Bool, reduceMotion: Bool) {
        let look = choice.look(hour: hour, weather: weather)
        let dioramaShown = choice == .suburbia && (weather == .clear || weather == .fog)
        if dioramaShown != usesDiorama {
            usesDiorama = dioramaShown
            apply()
        }
        diorama.reduceMotion = reduceMotion
        if !dioramaShown { flat.show(look.view, hour: look.hour, weather: look.weather, lampOn: lampOn) }
    }

    func place(window: [CGPoint], home: [CGPoint], hole: [CGPoint]) {
        placed = (window, home, hole)
        apply()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        apply()
    }

    private func apply() {
        let (window, home, hole) = placed
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backing.isHidden = hole.count < 3
        backing.frame = bounds
        backingClip.frame = bounds
        if hole.count > 2 { backingClip.path = Self.path(hole, grownBy: 1.03) }
        CATransaction.commit()
        diorama.place(window: usesDiorama ? window : [], home: home, hole: usesDiorama ? hole : [])
        flat.place(window: usesDiorama ? [] : window, home: usesDiorama ? [] : home, hole: usesDiorama ? [] : hole)
    }

    /// `dt` in seconds; call only while the window is on screen.
    func tick(_ dt: Double, hour: Float) {
        if abs(hour - skyHour) > 0.01 {
            skyHour = hour
            let sky = CityDiorama.sky(hour: hour)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            backing.colors = [Self.color(sky.top), Self.color(sky.horizon)]
            CATransaction.commit()
        }
        if usesDiorama { diorama.tick(Float(dt), hour: hour) } else { flat.tick(dt) }
    }

    private static func color(_ rgb: SIMD3<Float>) -> CGColor {
        UIColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1).cgColor
    }

    /// Grown about its middle so its edges hide behind the wall.
    private static func path(_ points: [CGPoint], grownBy factor: CGFloat) -> CGPath {
        let count = CGFloat(points.count)
        let centre = CGPoint(x: points.map(\.x).reduce(0, +) / count, y: points.map(\.y).reduce(0, +) / count)
        let path = CGMutablePath()
        path.addLines(between: points.map {
            CGPoint(x: centre.x + ($0.x - centre.x) * factor, y: centre.y + ($0.y - centre.y) * factor)
        })
        path.closeSubpath()
        return path
    }
}
