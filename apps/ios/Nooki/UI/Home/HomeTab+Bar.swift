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

    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// The tab whose slot holds `x` on a row of slots `width` wide, `x` from the row's leading edge; past the ends
    /// it is the first or last. Nil before the row has a width.
    static func at(_ x: CGFloat, across width: CGFloat) -> HomeTab? {
        guard width > 0 else { return nil }
        let index = Int((x / width * CGFloat(allCases.count)).rounded(.down))
        return allCases[min(max(index, 0), allCases.count - 1)]
    }
}
