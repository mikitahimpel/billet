import SwiftUI
import UIKit

// MARK: - Shop

struct ShopView: View {
    let state: HomeState

    @State private var selected: ShopCategory = .today
    @State private var sheetItem: ShopItem?
    @Namespace private var chip

    private let hMargin: CGFloat = 16
    /// Tab bar (66pt) + home-indicator area + breathing room, so the last row clears it.
    private let bottomInset: CGFloat = 134

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                    .padding(.horizontal, hMargin)
                CollectionHero(state: state) { sheetItem = $0 }
                    .padding(.horizontal, hMargin)
                chips
                if selected == .today {
                    RefreshLine()
                        .padding(.horizontal, hMargin)
                        .transition(.opacity)
                }
                grid
                    .padding(.horizontal, hMargin)
            }
            .padding(.top, 4)
            .padding(.bottom, bottomInset)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(.container, edges: .bottom)
        .sheet(item: $sheetItem) { item in
            ItemSheet(item: item, state: state)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Shop")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.primary)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)

            Spacer(minLength: 0)

            CoinPill(coins: state.coins)
        }
        .frame(height: 44)
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ShopCategory.allCases) { category in
                    chipButton(category)
                }
            }
            .padding(.vertical, 2)
        }
        // Keeps the first chip on the grid's margin while the next one peeks in on the right.
        .contentMargins(.horizontal, hMargin, for: .scrollContent)
        .scrollIndicators(.hidden)
    }

    private func chipButton(_ category: ShopCategory) -> some View {
        let isSelected = selected == category
        return Button {
            withAnimation(.spring(duration: 0.35)) { selected = category }
        } label: {
            Text(category.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Ink.primary : Ink.secondary)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.honey.opacity(0.32))
                            .matchedGeometryEffect(id: "shop-chip", in: chip)
                    } else {
                        Capsule()
                            .fill(.white.opacity(0.1))
                            .overlay(Capsule().stroke(Ink.hairline, lineWidth: 0.5))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Catalog.items(in: selected)) { item in
                ItemCard(item: item, state: state) {
                    sheetItem = item
                }
            }
        }
    }
}

// MARK: - Featured collection

/// The featured collection; a tap opens the next piece still missing from it.
private struct CollectionHero: View {
    let state: HomeState
    var open: (ShopItem) -> Void

    private let collection = Catalog.featured

    private var collected: Int {
        collection.itemIDs.count { state.owned.contains($0) }
    }

    private var progress: Double {
        Double(collected) / Double(max(collection.itemIDs.count, 1))
    }

    private var previews: [ShopItem] {
        collection.itemIDs.prefix(3).compactMap(Catalog.item)
    }

    private var next: ShopItem? {
        collection.itemIDs.compactMap(Catalog.item).first { !state.owned.contains($0.id) }
    }

    var body: some View {
        Button { if let next { open(next) } } label: { card }
            .buttonStyle(PressScaleStyle())
            .disabled(next == nil)
    }

    private var card: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xF6C891), Color(hex: 0xD98A55)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(collection.name)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Ink.heroInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(collection.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.heroInk.opacity(0.68))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 6)

                    Text("\(collected)/\(collection.itemIDs.count) collected")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Ink.heroInk.opacity(0.8))
                        .contentTransition(.numericText())

                    ProgressCapsule(value: progress)
                        .frame(width: 122)

                    if let next {
                        HStack(spacing: 5) {
                            Text("Next: \(next.name)")
                                .lineLimit(1)
                            CoinIcon(size: 14)
                            Text("\(Catalog.price(of: next))")
                                .monospacedDigit()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Ink.heroInk.opacity(0.78), in: .capsule)
                        .padding(.top, 4)
                    } else {
                        Text("Complete ✓")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Ink.heroInk)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                fan
                    .frame(width: 150, height: 126)
                    .padding(.bottom, 4)
            }
            .padding(18)
        }
        .frame(height: 190)
        .contentShape(.rect(cornerRadius: 28))
        .glass(.rect(cornerRadius: 28))
        .shadow(color: Color(hex: 0xD98A55).opacity(0.35), radius: 16, y: 8)
    }

    /// Three thumbnails fanned out: a bigger centre piece with two tilted wings tucked behind it.
    private var fan: some View {
        ZStack(alignment: .bottom) {
            ForEach(Array(previews.enumerated()), id: \.offset) { index, item in
                let isCentre = index == 1
                fanItem(item,
                        side: isCentre ? 88 : 64,
                        dx: CGFloat(index - 1) * 38,
                        degrees: isCentre ? 0 : (index == 0 ? -10 : 10))
                    .zIndex(isCentre ? 2 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// Fits the artwork into a square and drops it by the leftover space, so the pieces of
    /// different proportions still stand on the card's bottom edge.
    private func fanItem(_ item: ShopItem, side: CGFloat, dx: CGFloat, degrees: Double) -> some View {
        let lift = (side - fittedHeight(item, in: side)) / 2
        return thumbnail(item)
            .frame(width: side, height: side)
            .rotationEffect(.degrees(degrees))
            .offset(x: dx, y: lift)
    }

    private func fittedHeight(_ item: ShopItem, in side: CGFloat) -> CGFloat {
        guard let image = Thumbnails.trimmed(item.thumbnail), image.size.width > 0 else { return side }
        return min(side, side * image.size.height / image.size.width)
    }

    private func thumbnail(_ item: ShopItem) -> some View {
        Group {
            if let image = Thumbnails.trimmed(item.thumbnail) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "cube.box")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Ink.heroInk.opacity(0.3))
                    .padding(14)
            }
        }
        .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
    }
}

// MARK: - Refresh countdown

private struct RefreshLine: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .semibold))
                Text("Refreshes in \(Self.remaining(until: context.date))")
                    .font(.system(size: 13, weight: .medium))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(Ink.secondary)
        }
    }

    private static func remaining(until date: Date) -> String {
        let calendar = Calendar.current
        guard let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) else {
            return "0h 0m"
        }
        let seconds = max(0, Int(midnight.timeIntervalSince(date)))
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }
}

// MARK: - Item card

private struct ItemCard: View {
    let item: ShopItem
    let state: HomeState
    var onTap: () -> Void

    private var isDeal: Bool { item.id == Catalog.dealID }
    private var owned: Bool { state.owned.contains(item.id) }
    private var gifted: Bool { state.gifted.contains(item.id) }

    var body: some View {
        // The whole card is a single plain Button: the press effect lives in the
        // ButtonStyle (configuration.isPressed), so no extra gesture competes with the
        // tap inside the ScrollView and the action always sets the sheet item.
        Button(action: onTap) {
            card
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(item.name)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail
            nameRow
            Spacer(minLength: 0)
            priceRow
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(0.08))
        }
        // Every point of the card opens the item, the gaps between its rows included.
        .contentShape(.rect(cornerRadius: 24))
        .glass(.rect(cornerRadius: 24))
    }

    private var thumbnail: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFFE9C9).opacity(0.35), .clear],
                                     center: .center, startRadius: 2, endRadius: 92))
                .padding(6)

            if let image = Thumbnails.image(item.thumbnail, maxPixels: 512) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                Image(systemName: "cube.box")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.28))
                    .padding(40)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            badge
        }
    }

    @ViewBuilder private var badge: some View {
        if isDeal {
            badgePill("-20%", background: AnyShapeStyle(Color(hex: 0xFF7A93)))
        } else if item.isPlus {
            badgePill("PLUS", background: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xB79CF2), Color(hex: 0x8A6FE0)],
                                                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
        } else if item.isNew {
            badgePill("NEW", background: AnyShapeStyle(Color.honey))
        }
    }

    private func badgePill(_ text: String, background: AnyShapeStyle) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(background, in: .capsule)
            .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
    }

    private var nameRow: some View {
        HStack(spacing: 5) {
            Text(item.name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.primary)
                .lineLimit(1)

            if gifted {
                Image(systemName: "gift.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.honey)
            }

            Spacer(minLength: 0)
        }
        .frame(height: 18)
    }

    /// The price as the card's call to action: a filled pill when the wallet covers it.
    private var priceRow: some View {
        HStack(spacing: 6) {
            if owned {
                Label("Owned", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.honey)
                    .frame(height: 32)
            } else {
                let affordable = state.coins >= Catalog.price(of: item)
                HStack(spacing: 5) {
                    CoinIcon(size: 16)
                    Text("\(Catalog.price(of: item))")
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                    if isDeal {
                        Text("\(item.price)")
                            .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                            .strikethrough()
                            .opacity(0.7)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: affordable ? "bag.fill" : "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.leading, 6)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background {
                    if affordable {
                        Capsule().fill(.honeyGradient)
                    } else {
                        Capsule().fill(.white.opacity(0.12))
                    }
                }
                .shadow(color: affordable ? Color.honeyDeep.opacity(0.35) : .clear, radius: 6, y: 3)
            }
            Spacer(minLength: 0)
        }
    }

}
