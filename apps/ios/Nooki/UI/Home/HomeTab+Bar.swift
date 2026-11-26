import BilletKit
import CoreGraphics

/// A tab as the tab bar shows it, in `allCases` order, left to right, each in an equal slot.
extension HomeTab {
    var title: String {
        switch self {
        case .world: "World"
        case .moments: "Moments"
        case .shop: "Shop"
        case .us: "Us"
        }
    }

    var symbol: String {
        switch self {
        case .world: "house.fill"
        case .moments: "photo.on.rectangle"
        case .shop: "bag"
        case .us: "heart"
        }
    }

    /// Dusk's bar: the chosen tab's symbol fills in, the rest stay outlined.
    func symbol(filled: Bool) -> String {
        switch self {
        case .world: filled ? "house.fill" : "house"
        case .moments: filled ? "photo.fill.on.rectangle.fill" : "photo.on.rectangle"
        case .shop: filled ? "bag.fill" : "bag"
        case .us: filled ? "heart.fill" : "heart"
        }
    }

    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// The tab whose slot holds `x` on a row of slots `width` wide, `x` from the row's leading edge; past the ends
    /// it is the first or last. Nil before the row has a width.
    static func at(_ x: CGFloat, across width: CGFloat) -> HomeTab? {
        guard width > 0 else { return nil }
        let index = Int((x / width * CGFloat(allCases.count)).rounded(.down))
        return allCases[min(max(index, 0), allCases.count - 1)]
    }
}

/// The finger on the tab bar. The tab under it is shown the moment it lands or slides there, and lifting it changes
/// nothing more, so a tap's page comes with the pill and not a tap's length after it. Only the bar reads the store,
/// so a touch on it never runs Home's body.
nonisolated enum TabBarMachine: Machine {
    enum State: Equatable, Sendable {
        case idle
        /// The tab under the finger.
        case touched(HomeTab)

        var hovered: HomeTab? {
            switch self {
            case .idle: nil
            case .touched(let tab): tab
            }
        }
    }

    enum Event: Equatable, Sendable {
        /// The finger is on this tab's slot: it landed there, or slid onto it.
        case landed(HomeTab)
        case lifted
    }

    enum Output: Equatable, Sendable {}

    static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
        switch (state, event) {
        case (.idle, .landed(let tab)), (.touched, .landed(let tab)):
            return (.touched(tab), [])
        case (.touched, .lifted):
            return (.idle, [])
        // A gesture that was cancelled ends twice: by its state resetting and by its own end.
        case (.idle, .lifted):
            return (state, [])
        }
    }
}
