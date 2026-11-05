import PetScene
import SwiftUI

// MARK: - Shop

/// The Shop tab under the app header: category chips, then Today's offers (the free gift, the week's featured set,
/// the daily deals, bundles and collections) or a category's grid. Every price is in coins and every countdown ends
/// at a real rotation.
struct ShopView: View {
    let state: HomeState

    @State private var selected: ShopCategory = .today
    @State private var sheetItem: ShopItem?
    /// Where the page is scrolled to; a perf run moves it (`NookiPerf.shopScroll`).
    @State private var position = ScrollPosition(edge: .top)

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
                .padding(.top, 4)
                .padding(.bottom, Space.l)
                .animation(.spring(duration: 0.35), value: selected)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($position)
            .onAppear {
                guard ScenePerf.isOn else { return }
                NookiPerf.shopScroll = { position.scrollTo(y: $0) }
            }
            .onDisappear { NookiPerf.shopScroll = nil }
            .task {
                #if DEBUG
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
    }

    // MARK: Categories

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.s) {
                ForEach(ShopCategory.allCases) { category in
                    let isSelected = selected == category
                    Button(category.title) { selected = category }
                        .shopButton(prominent: isSelected)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .contentMargins(.horizontal, Space.l, for: .scrollContent)
        .scrollIndicators(.hidden)
    }

    // MARK: Today

    @ViewBuilder private var today: some View {
        let now = Date.now
        DailyGiftCard(state: state)
            .padding(.horizontal, Space.l)

        FeaturedCard(state: state, offer: state.offers.featured(on: now))
            .padding(.horizontal, Space.l)

        VStack(alignment: .leading, spacing: Space.m) {
            sectionHeader("Daily deals") {
                // Deals change at the couple's local midnight, the same for both of them.
                Label {
                    Text(timerInterval: now...state.offers.nextDay(after: now), countsDown: true)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "clock")
                }
                .accessibilityLabel("New deals at midnight")
            }
            grid(state.offers.deals(on: now).compactMap { Catalog.item($0.itemID) })
        }
        .padding(.horizontal, Space.l)
        .id("deals")

        VStack(alignment: .leading, spacing: Space.m) {
            sectionHeader("Bundles") { Text("Less than one by one") }
            ForEach(ShopOffers.bundles, id: \.id) { bundle in
                BundleCard(state: state, bundle: bundle) { sheetItem = $0 }
            }
        }
        .padding(.horizontal, Space.l)
        .id("bundles")

        VStack(alignment: .leading, spacing: Space.m) {
            sectionHeader("Inks") { Text("For notes and drawings") }
                .padding(.horizontal, Space.l)
            InkShelf(state: state)
        }
        .id("inks")

        VStack(alignment: .leading, spacing: Space.m) {
            sectionHeader("Collections") { Text("A bonus for each full set") }
            ForEach(Catalog.collections) { collection in
                CollectionCard(state: state, collection: collection) { sheetItem = $0 }
            }
        }
        .padding(.horizontal, Space.l)
        .id("collections")

        Text("Earn coins by answering together, keeping your streak, opening the daily gift and completing collections.")
            .font(.nookiCaption)
            .foregroundStyle(Ink.textSecondary)
            .padding(.horizontal, Space.l)
    }

    private func sectionHeader(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.nookiTitle)
                .foregroundStyle(Ink.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s)
            trailing()
                .font(.nookiCaption)
                .foregroundStyle(Ink.textSecondary)
        }
    }

    private func grid(_ items: [ShopItem]) -> some View {
        LazyVGrid(columns: columns, spacing: Space.m) {
            ForEach(items) { item in
                ShopItemCard(item: item, state: state) { sheetItem = item }
            }
        }
    }
}
