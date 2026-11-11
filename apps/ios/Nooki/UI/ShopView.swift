import PetScene
import SwiftUI
import Design

// MARK: - Shop

/// Every price is in coins and every countdown ends at a real rotation.
struct ShopView: View {
    let state: HomeState

    @State private var sheetItem: ShopItem?
    @State private var sheetSet: SetChoice?
    /// The ink the Shop was opened at, ringed on the Inks shelf for a moment.
    @State private var highlightedInk: String?
    @State private var scrolling = ShopScrolling()

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.section) {
                    switch state.shopCategory {
                    case .today:
                        today
                    case .inks:
                        InkShelf(state: state, highlighted: highlightedInk)
                    case .furniture, .decor, .mochi, .room:
                        grid(Catalog.items(in: state.shopCategory))
                            .padding(.horizontal, Space.l)
                    }
                }
                .tabContentInsets()
                .animation(.spring(duration: 0.35), value: state.shopCategory)
            }
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, phase in
                if scrolling.isScrolling != phase.isScrolling { scrolling.isScrolling = phase.isScrolling }
            }
            .environment(scrolling)
            .softScrollEdges()
            .onChange(of: state.shopFocus, initial: true) { _, focus in
                guard let focus else { return }
                switch focus {
                case .ink(let id):
                    state.shopCategory = .inks
                    Task {
                        highlightedInk = id
                        state.shopFocus = nil
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(.easeOut(duration: 0.4)) { if highlightedInk == id { highlightedInk = nil } }
                    }
                case .item(let id):
                    state.shopCategory = .today
                    sheetItem = Catalog.item(id)
                    state.shopFocus = nil
                }
            }
            .task {
                #if DEBUG
                // `-shopItem tower` on launch opens that item's sheet, for screenshots.
                if let id = UserDefaults.standard.string(forKey: "shopItem") { sheetItem = Catalog.item(id) }
                // `-shopSet featured` (or a bundle's id) opens that set's sheet.
                if let id = UserDefaults.standard.string(forKey: "shopSet") {
                    if id == "featured" {
                        sheetSet = SetChoice(pieces: state.shop.offers.featured(on: .now))
                    } else if let bundle = ShopOffers.bundles.first(where: { $0.id == id }) {
                        sheetSet = SetChoice(pieces: bundle)
                    }
                }
                // `-shopSection bundles` (or deals, collections) on launch scrolls Today there, for screenshots.
                guard let section = UserDefaults.standard.string(forKey: "shopSection") else { return }
                try? await Task.sleep(for: .milliseconds(300))
                reader.scrollTo(section, anchor: .top)
                #endif
            }
        }
        .task {
            // The cards draw their art at 512 px and the bundles and collections at 256: decoded now, off the main
            // thread, the first scroll down the page doesn't stop for each picture.
            let names = Catalog.items.map(\.thumbnail)
            await Thumbnails.prefetch(names, maxPixels: 512)
            await Thumbnails.prefetch(names, maxPixels: 256)
        }
        .sheet(item: $sheetItem) { item in
            ItemSheet(item: item, state: state)
        }
        .sheet(item: $sheetSet) { choice in
            SetSheet(state: state, pieces: choice.pieces)
        }
    }

    // MARK: Today

    @ViewBuilder private var today: some View {
        let now = Date.now
        FeaturedCard(state: state, offer: state.shop.offers.featured(on: now)) { sheetSet = SetChoice(pieces: $0) }
            .padding(.horizontal, Space.l)
            .shopAppear()

        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("Daily deals", symbol: "tag.fill", tint: ShopInk.coral) {
                // Deals change at the couple's local midnight, the same for both of them.
                Label {
                    Text(timerInterval: now...state.shop.offers.nextDay(after: now), countsDown: true)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "clock")
                }
                .accessibilityLabel("New deals at midnight")
            }
            dealsRow(state.shop.offers.deals(on: now).compactMap { Catalog.item($0.itemID) })
        }
        .id("deals")

        DailyGiftCard(state: state)
            .padding(.horizontal, Space.l)
            .shopAppear()

        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("Bundles", symbol: "shippingbox.fill", tint: ShopInk.plum) {
                Text("Less than one by one")
            }
            ForEach(ShopOffers.bundles, id: \.id) { bundle in
                BundleCard(state: state, bundle: bundle, open: { sheetItem = $0 }) { sheetSet = SetChoice(pieces: bundle) }
                    .shopAppear()
            }
        }
        .padding(.horizontal, Space.l)
        .id("bundles")

        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("Collections", symbol: "square.grid.2x2.fill", tint: ShopInk.teal) {
                Text("A bonus for each full set")
            }
            ForEach(Catalog.collections) { collection in
                CollectionCard(state: state, collection: collection) { sheetItem = $0 }
                    .shopAppear()
            }
        }
        .padding(.horizontal, Space.l)
        .id("collections")

        Text("Earn coins by answering together, keeping your streak, opening the daily gift and completing collections.")
            .font(.ourioCaption)
            .foregroundStyle(Ink.textSecondary)
            .padding(.horizontal, Space.l)
    }

    /// The day's deals side by side in one row that scrolls sideways, each tile as wide as a grid tile on an iPhone.
    private func dealsRow(_ items: [ShopItem]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Space.m) {
                ForEach(items) { item in
                    ShopItemCard(item: item, state: state) { sheetItem = item }
                        .frame(width: ShopLayout.dealWidth)
                }
            }
            .padding(.horizontal, Space.l)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func grid(_ items: [ShopItem]) -> some View {
        ItemGrid {
            ForEach(items) { item in
                ShopItemCard(item: item, state: state) { sheetItem = item }
                    .shopAppear()
            }
        }
    }

    /// Decodes the art Today shows first, the featured set and the deals, off the main thread, so the first visit to
    /// the Shop doesn't decode it in front of the tap.
    static func prewarm(_ offers: ShopOffers, now: Date = .now) async {
        let featured = offers.featured(on: now).itemIDs.compactMap(Catalog.item).map(\.thumbnail)
        let deals = offers.deals(on: now).compactMap { Catalog.item($0.itemID)?.thumbnail }
        await Thumbnails.prefetchTrimmed(featured)
        await Thumbnails.prefetch(deals, maxPixels: 512)
    }

}

/// The Shop's shelves in one row that scrolls sideways, in the header's slot under its controls: pinned with the
/// header, over the page's own soft edge, so no band is drawn behind them.
struct ShopChips: View {
    @Bindable var state: HomeState

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.s) {
                ForEach(ShopCategory.allCases) { category in
                    FilterChip(category.title, symbol: category.symbol, isSelected: state.shopCategory == category) {
                        state.shopCategory = category
                    }
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        // Edge to edge: the header pads its row by `Space.l`, the chips scroll out from under the screen's edges.
        .padding(.horizontal, -Space.l)
        .haptic(.selection, trigger: state.shopCategory)
    }
}
