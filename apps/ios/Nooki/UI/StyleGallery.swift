import Design
import SwiftUI

/// Settings → Labs → Style: the design package's tokens and components, drawn by the same code the screens use,
/// so docs/design-system.md can be checked on a device in either appearance.
struct StyleGallery: View {
    @State private var dark = true
    @State private var chip = 0
    @State private var isOn = true

    var body: some View {
        Page {
            GroupedSection(header: "Colour") {
                swatch("Ink.screen", Ink.screen)
                swatch("Ink.surface", Ink.surface)
                swatch("Ink.surfaceRaised", Ink.surfaceRaised)
                swatch("Ink.accentText", Ink.accentText)
                swatch("Color.honey", .honey)
            }
            GroupedSection(header: "Type", inset: Space.l) {
                Text("Large title").font(.nookiLargeTitle).rowCell()
                Text("Title").font(.nookiTitle).rowCell()
                Text("Headline").font(.nookiHeadline).rowCell()
                Text("Body").font(.nookiBody).rowCell()
                Text("Caption").font(.nookiCaption).foregroundStyle(Ink.textSecondary).rowCell()
            }
            VStack(spacing: Space.m) {
                PrimaryButton("Primary", symbol: "heart.fill") {}
                PrimaryButton("Disabled primary") {}.disabled(true)
                SecondaryButton("Secondary") {}
            }
            GroupedSection(header: "Rows") {
                Row("Opens a screen", symbol: "person.2.fill", tint: UsTint.sky.color) { RowChevron() }
                ToggleRow("A switch", symbol: "hand.tap.fill", isOn: $isOn)
                Row("Erase all data", symbol: "trash.fill", tint: UsTint.coral.color, destructive: true)
            }
            GroupedSection(header: "Chips", inset: Space.l) {
                HStack {
                    ForEach(["Today", "Cats", "Rooms"].indices, id: \.self) { index in
                        FilterChip(["Today", "Cats", "Rooms"][index], isSelected: chip == index) { chip = index }
                    }
                }
                .rowCell()
                HStack {
                    Chip("Rare", style: .tinted(.teal))
                    Chip("-20%", style: .honey)
                    Chip("Owned", symbol: "checkmark")
                }
                .rowCell()
            }
            Card {
                HStack {
                    GlassIconButton(symbol: "face.smiling", label: "Mood") {}
                    GlassIconButton(symbol: "tray", label: "Inbox", badge: .dot) {}
                    Spacer()
                    Design.PriceButton(120) {}
                }
            }
            Card {
                EmptyState(symbol: "photo.on.rectangle", title: "No moments yet", text: "Your first photo together will live here.") {
                    PrimaryButton("Add a moment", fullWidth: false) {}
                }
            }
        }
        .navigationTitle("Style")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(dark ? "Light" : "Dark") { dark.toggle() }
            }
        }
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private func swatch(_ name: String, _ colour: Color) -> some View {
        HStack(spacing: Space.m) {
            RoundedRectangle(cornerRadius: Radius.inner)
                .fill(colour)
                .overlay { RoundedRectangle(cornerRadius: Radius.inner).stroke(Ink.separator) }
                .frame(width: 36, height: 28)
            Text(name).font(.nookiCallout).foregroundStyle(Ink.text)
        }
        .rowCell()
    }
}
