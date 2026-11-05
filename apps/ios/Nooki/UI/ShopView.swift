import SwiftUI

// MARK: - Shop

/// The Shop tab under the app header: category chips, then Today's offers (the free gift, the week's featured set,
/// the daily deals) or a category's grid. Every price is in coins and every countdown ends at a real rotation.
struct ShopView: View {
    let state: HomeState

    @State private var selected: ShopCategory = .today
    @State private var sheetItem: ShopItem?

    /// Tab bar (66pt) + home-indicator area + breathing room, so the last row clears it.
    private let bottomInset: CGFloat = 134

    private let columns = [
        GridItem(.flexible(), spacing: Space.m, alignment: .top),
        GridItem(.flexible(), spacing: Space.m, alignment: .top),
    ]

    var body: some View {
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
            .padding(.bottom, bottomInset)
            .animation(.spring(duration: 0.35), value: selected)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(.container, edges: .bottom)
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

        CollectionHero(state: state) { sheetItem = $0 }
            .padding(.horizontal, Space.l)

        Text("Earn coins by answering together, keeping your streak and opening the daily gift.")
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
