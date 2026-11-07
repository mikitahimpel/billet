import PetScene
import SwiftUI
import Design

// MARK: - Shop

/// The Shop tab under the app header: category chips, then Today's offers (the week's featured set as the hero, the
/// daily deals, the free gift, bundles, inks, collections and the coins) or a category's grid. Every price is in coins and every
/// countdown ends at a real rotation.
struct ShopView: View {
    let state: HomeState

    @State private var selected: ShopCategory = .today
    @State private var sheetItem: ShopItem?
    @State private var sheetSet: SetChoice?
    /// The ink the Shop was opened at, ringed on the Inks shelf for a moment.
    @State private var highlightedInk: String?
    /// Where the page is scrolled to; a perf run moves it (`NookiPerf.scrolls`).
    @State private var position = ScrollPosition(edge: .top)
    @AppStorage(AppSettings.shopLightKey) private var lightEffects = false

    private let columns = [
        GridItem(.flexible(), spacing: Space.m, alignment: .top),
        GridItem(.flexible(), spacing: Space.m, alignment: .top),
    ]

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    chips
                    if selected == .today {
                        today
                    } else {
                        grid(Catalog.items(in: selected))
                            .padding(.horizontal, Space.l)
                    }
                }
                .padding(.top, Space.s)
                .padding(.bottom, Space.l)
                .animation(.spring(duration: 0.35), value: selected)
            }
            .scrollIndicators(.hidden)
            .shopScrollEdges()
            .scrollPosition($position)
            .environment(\.shopLightEffects, lightEffects)
            .softScrollEdges()
            .onAppear {
                guard ScenePerf.isOn else { return }
                NookiPerf.scrolls[.shop] = { position.scrollTo(y: $0) }
            }
            .onDisappear { NookiPerf.scrolls[.shop] = nil }
            .onChange(of: state.shopFocus, initial: true) { _, focus in
                guard let focus else { return }
                selected = .today
                switch focus {
                case .ink(let id):
                    // After Today has laid out, so the Inks block is there to scroll to.
                    Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        withAnimation(.spring(duration: 0.45)) { reader.scrollTo("inks", anchor: .top) }
                        highlightedInk = id
                        state.shopFocus = nil
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(.easeOut(duration: 0.4)) { if highlightedInk == id { highlightedInk = nil } }
                    }
                case .item(let id):
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
        .haptic(.selection, trigger: selected)
        .sheet(item: $sheetItem) { item in
            ItemSheet(item: item, state: state)
        }
        .sheet(item: $sheetSet) { choice in
            SetSheet(state: state, pieces: choice.pieces)
        }
    }

    // MARK: Categories

    /// The categories in one row that scrolls sideways; the page under it only scrolls up and down.
    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.s) {
                ForEach(ShopCategory.allCases) { category in
                    let isSelected = selected == category
                    FilterChip(category.title, isSelected: isSelected) { selected = category }
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
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
            grid(state.shop.offers.deals(on: now).compactMap { Catalog.item($0.itemID) })
        }
        .padding(.horizontal, Space.l)
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
            SectionHeader("Inks", symbol: "paintpalette.fill", tint: .honey) {
                Text("For notes and drawings")
            }
            .padding(.horizontal, Space.l)
            InkShelf(state: state, highlighted: highlightedInk)
        }
        .id("inks")

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
            .font(.nookiCaption)
            .foregroundStyle(Ink.textSecondary)
            .padding(.horizontal, Space.l)
    }

    private func grid(_ items: [ShopItem]) -> some View {
        LazyVGrid(columns: columns, spacing: Space.m) {
            ForEach(items) { item in
                ShopItemCard(item: item, state: state) { sheetItem = item }
                    .shopAppear()
            }
        }
    }
}

private extension View {
    /// A solid fade under the header and the tab bar instead of the soft one: cards scrolling under clear glass
    /// would otherwise show through it as a ghost.
    @ViewBuilder
    func shopScrollEdges() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectStyle(.hard, for: .vertical)
        } else {
            self
        }
    }
}
