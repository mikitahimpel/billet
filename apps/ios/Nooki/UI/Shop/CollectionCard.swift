import SwiftUI
import Design

/// The bonus can be collected once every piece is owned.
struct CollectionCard: View {
    let state: HomeState
    let collection: ShopCollection
    var open: (ShopItem) -> Void

    @State private var claims = 0
    @State private var collecting = false

    private var items: [ShopItem] { collection.itemIDs.compactMap(Catalog.item) }
    private var have: Int { collection.owned(of: state.shop.owned) }
    private var claimed: Bool { state.shop.bonuses.contains(collection.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(collection.name)
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: Space.s)
                Text("\(have)/\(collection.itemIDs.count)")
                    .font(.ourioHeadline.monospacedDigit())
                    .foregroundStyle(Ink.accentText)
                    .contentTransition(.numericText())
            }
            ProgressView(value: Double(have), total: Double(collection.itemIDs.count))
                .tint(.honey)
                .accessibilityLabel("\(have) of \(collection.itemIDs.count) collected")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 4), spacing: Space.s) {
                ForEach(items) { item in
                    slot(item)
                }
            }

            bonus
        }
        .padding(CardMetrics.padding)
        .cardSurface()
        .haptic(.success, trigger: claims)
        .animation(.spring(duration: 0.35), value: have)
    }

    private func slot(_ item: ShopItem) -> some View {
        let owns = state.shop.owned.contains(item.id)
        return Button { open(item) } label: {
            Group {
                if let image = Thumbnails.image(item.thumbnail, maxPixels: 256) {
                    Image(uiImage: image).resizable().scaledToFit().padding(Space.xs)
                }
            }
            .grayscale(owns ? 0 : 1)
            .opacity(owns ? 1 : 0.4)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Ink.surfaceRaised, in: .rect(cornerRadius: Radius.inner, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if owns { OwnedCheck().offset(x: 3, y: 3) }
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(item.name + (owns ? ", owned" : ", missing"))
    }

    @ViewBuilder private var bonus: some View {
        HStack(spacing: Space.s) {
            Image(systemName: claimed ? "checkmark.seal.fill" : "sparkles")
                .foregroundStyle(Color.honey)
                .accessibilityHidden(true)
            Group {
                if claimed {
                    Text("Bonus collected: \(collection.bonus) coins")
                } else {
                    Text("Complete it for \(collection.bonus) coins")
                }
            }
            .font(.ourioCallout)
            .foregroundStyle(Ink.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            if state.shop.canClaimBonus(collection) {
                PrimaryButton("Collect", fullWidth: false) {
                    collecting = true
                    Task {
                        if await state.shop.claimBonus(collection) { claims += 1 }
                        collecting = false
                    }
                }
                .disabled(collecting)
            }
        }
        .padding(Space.m)
        .background(Ink.surfaceRaised, in: .rect(cornerRadius: Radius.inner, style: .continuous))
    }
}
