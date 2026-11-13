import CoreGraphics
import Foundation
import Pet
import WindowViews

/// What the City room's window looks out on, as chosen in Settings → Labs. A build without Labs always shows `defaultChoice`.
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

    static let defaultChoice = WindowChoice.suburbia

    static var current: WindowChoice {
        #if DEBUG || LABS_YES
        UserDefaults.standard.string(forKey: key).flatMap(WindowChoice.init(rawValue:)) ?? defaultChoice
        #else
        defaultChoice
        #endif
    }

    /// The weather Suburbia shows; the named views keep their own.
    static var weather: ViewWeather {
        #if DEBUG || LABS_YES
        UserDefaults.standard.string(forKey: weatherKey).flatMap(ViewWeather.init(rawValue:)) ?? .clear
        #else
        .clear
        #endif
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
