import Pet
import UIKit
import WindowViews

/// The Bedroom's window: the street as clay image layers by default, and the flat painted views when Settings
/// asks for one of them or the weather is rain or snow. Told the same things as the flat view, it passes them on.
@MainActor
final class CityWindowView: UIView {
    private let flat = FlatWindowView()
    private let diorama = CityDioramaView()
    private var usesDiorama = true
    private var placed: (window: [CGPoint], home: [CGPoint], hole: [CGPoint]) = ([], [], [])

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
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

    private func apply() {
        let (window, home, hole) = placed
        diorama.place(window: usesDiorama ? window : [], home: home, hole: usesDiorama ? hole : [])
        flat.place(window: usesDiorama ? [] : window, home: usesDiorama ? [] : home, hole: usesDiorama ? [] : hole)
    }

    /// `dt` in seconds; call only while the window is on screen.
    func tick(_ dt: Double, hour: Float) {
        if usesDiorama { diorama.tick(Float(dt), hour: hour) } else { flat.tick(dt) }
    }
}
