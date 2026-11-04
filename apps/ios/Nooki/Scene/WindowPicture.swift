import CoreGraphics
import Foundation
import Pet
import WindowViews

/// What the City room's window looks out on, as chosen in Settings.
enum WindowChoice: String, CaseIterable, Identifiable {
    /// The suburb for the hour and weather: the cul-de-sac by day, the suburb at night, the rainy suburb in rain and
    /// the December street in snow.
    case suburbia
    case suburbNight
    case summerCulDeSac
    case rainySuburb
    case snowyDecember

    static let key = "windowView"
    static let weatherKey = "windowWeather"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .suburbia: "Suburbia"
        case .suburbNight: WindowView.suburbNight.title
        case .summerCulDeSac: WindowView.summerCulDeSac.title
        case .rainySuburb: WindowView.rainySuburb.title
        case .snowyDecember: WindowView.snowyDecember.title
        }
    }

    static var current: WindowChoice {
        UserDefaults.standard.string(forKey: key).flatMap(WindowChoice.init(rawValue:)) ?? .suburbia
    }

    /// The weather Suburbia shows; the named views keep their own.
    static var weather: ViewWeather {
        UserDefaults.standard.string(forKey: weatherKey).flatMap(ViewWeather.init(rawValue:)) ?? .clear
    }

    /// The view, its light and its weather at `hour` (0–24).
    func look(hour: Float, weather: ViewWeather) -> (view: WindowView, hour: ViewHour, weather: ViewWeather) {
        let shownHour = ViewHour(DayLight.at(hour: Double(hour)).phase)
        switch self {
        case .suburbia:
            let view: WindowView =
                switch weather {
                case .rain: .rainySuburb
                case .snow: .snowyDecember
                case .clear, .fog: shownHour == .night ? .suburbNight : .summerCulDeSac
                }
            return (view, shownHour, weather)
        case .suburbNight: return (.suburbNight, shownHour, WindowView.suburbNight.weather)
        case .summerCulDeSac: return (.summerCulDeSac, shownHour, WindowView.summerCulDeSac.weather)
        case .rainySuburb: return (.rainySuburb, shownHour, WindowView.rainySuburb.weather)
        case .snowyDecember: return (.snowyDecember, shownHour, WindowView.snowyDecember.weather)
        }
    }
}

/// The City room window's picture: the chosen view painted for the hour, with its life redrawn a few times a second.
/// Each frame is one image for the pane's texture, so nothing is layered over the 3D view.
final class WindowPicture {
    /// How often the view's life is redrawn.
    static let rate: Float = 12
    static let size = CGSize(width: 640, height: 352)

    private let painter = WindowPainter(size: WindowPicture.size)
    private var age: Float = .infinity
    private var choiceAge: Float = .infinity
    private var choice = WindowChoice.current
    private var weather = WindowChoice.weather
    private var moves = false

    /// The next frame for the pane, or `nil` when the one shown still stands. Changing views or the hour's part of the
    /// day repaints at once.
    func image(after dt: Float, hour: Float) -> CGImage? {
        age += dt
        choiceAge += dt
        // Settings are read once a second rather than every frame.
        if choiceAge > 1 {
            choiceAge = 0
            choice = WindowChoice.current
            weather = WindowChoice.weather
        }
        let look = choice.look(hour: hour, weather: weather)
        let changed = painter.prepare(look.view, hour: look.hour, weather: look.weather)
        if changed { moves = WindowPainter.moves(look.view) }
        guard changed || (moves && age >= 1 / Self.rate) || age > 4 else { return nil }
        age = 0
        return painter.frame()
    }
}
