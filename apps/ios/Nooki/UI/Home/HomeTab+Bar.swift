import Design

/// A tab as the tab bar shows it, in `allCases` order, left to right.
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

    /// Its slot in the bar, counted from the leading edge.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// Which way the screen moves when the bar goes from `old` to `new`: forward is to a tab on the right.
    static func direction(from old: HomeTab, to new: HomeTab) -> Motion.Direction {
        Motion.Direction(from: old.order, to: new.order)
    }
}
