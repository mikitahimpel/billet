import SwiftUI

// MARK: - Featured collection

/// The featured collection; a tap opens the next piece still missing from it.
struct CollectionHero: View {
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
                            Text("\(state.price(of: next))")
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

