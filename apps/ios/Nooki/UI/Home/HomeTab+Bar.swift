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

/// The finger on the tab bar, as a value. The tab under it is shown the moment it lands or slides there, and
/// lifting it changes nothing more, so a tap's page comes with the pill and not a tap's length after it.
struct TabScrub: Equatable {
    /// The tab under the finger; nil while the bar is not touched.
    var hovered: HomeTab?

    struct Move: Equatable {
        let scrub: TabScrub
        /// The tab to show, when it isn't the shown one yet.
        let shows: HomeTab?
    }

    init(hovered: HomeTab? = nil) {
        self.hovered = hovered
    }

    /// The finger lands on, or slides onto, `tab` while `shown` is on screen; nil while it stays in the same slot.
    func finger(on tab: HomeTab, shown: HomeTab) -> Move? {
        guard tab != hovered else { return nil }
        return Move(scrub: TabScrub(hovered: tab), shows: tab == shown ? nil : tab)
    }

    func lifted() -> TabScrub { TabScrub() }
}
