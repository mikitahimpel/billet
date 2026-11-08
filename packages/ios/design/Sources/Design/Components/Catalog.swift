import SwiftUI

private struct Catalog: View {
  @State private var room = "Room"
  @State private var isOn = true

  private let inks: [(String, Color)] = [
    ("screen", Ink.screen), ("surface", Ink.surface), ("surfaceRaised", Ink.surfaceRaised),
    ("text", Ink.text), ("textSecondary", Ink.textSecondary), ("textTertiary", Ink.textTertiary),
    ("accentText", Ink.accentText), ("destructive", Ink.destructive), ("heroInk", Ink.heroInk),
    ("glassFill", Ink.glassFill), ("glassGlyph", Ink.glassGlyph),
    ("disabledFill", Ink.disabledFill),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.section) {
        SectionHeader("Ink")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Space.s)], spacing: Space.s)
        {
          ForEach(inks, id: \.0) { name, color in
            VStack(spacing: Space.xs) {
              RoundedRectangle(cornerRadius: Radius.tag).fill(color).frame(height: 36)
                .overlay(RoundedRectangle(cornerRadius: Radius.tag).strokeBorder(Ink.separator))
              Text(name).font(.nookiMicro).foregroundStyle(Ink.textSecondary)
            }
          }
        }

        SectionHeader("Type")
        VStack(alignment: .leading, spacing: Space.xs) {
          Text("Large title").font(.nookiLargeTitle)
          Text("Title").font(.nookiTitle)
          Text("Headline").font(.nookiHeadline)
          Text("Body").font(.nookiBody)
          Text("Callout").font(.nookiCallout)
          Text("Caption").font(.nookiCaption)
          Text("Micro").font(.nookiMicro)
        }
        .foregroundStyle(Ink.text)

        SectionHeader("Space and Radius")
        HStack(alignment: .bottom, spacing: Space.s) {
          ForEach(
            [Space.xs, Space.s, Space.m, Space.l, Space.gutter, Space.section, Space.xl], id: \.self
          ) {
            Rectangle().fill(Ink.accentText).frame(width: $0, height: $0)
          }
          Spacer()
          ForEach([Radius.tag, Radius.control, Radius.card, Radius.hero], id: \.self) {
            RoundedRectangle(cornerRadius: $0).fill(Ink.surfaceRaised).frame(width: 40, height: 40)
          }
        }

        SectionHeader("Buttons")
        PrimaryButton("Share with Ilya") {}
        PrimaryButton("Pick how you feel") {}.disabled(true)
        HStack {
          SecondaryButton("Place", symbol: "mappin") {}
          SecondaryButton("Place", symbol: "mappin") {}.disabled(true)
        }

        SectionHeader("Labels")
        HStack {
          Chip("Rare", style: .tinted(.teal))
          Chip("−20%", style: .honey)
          Chip("Owned", symbol: "checkmark")
          FilterChip("Today", isSelected: true) {}
          FilterChip("Cats", isSelected: false) {}
        }
        HStack {
          PriceButton(120) {}
          PriceButton(90, was: 125) {}
          CoinIcon(size: 28)
        }

        SectionHeader("Rows")
        GroupedSection(header: "Settings", footer: "Haptics are only on this phone.") {
          Row("Profile", detail: "Mikita", symbol: "person.fill") { RowChevron() }
          ToggleRow("Haptics", symbol: "hand.tap.fill", tint: .blushPink, isOn: $isOn)
          Row("Erase all data", symbol: "trash.fill", destructive: true)
        }
        Card(warm: true) { Text("A hero card").font(.nookiHeadline).foregroundStyle(Ink.text) }
        EmptyState(symbol: "tray", title: "All quiet", text: "Notes and gifts show up here.")
      }
      .padding(Space.gutter)
    }
    .background(Ink.screen)
  }
}

private struct HeaderOverRoom: View {
  @State private var room = "Room"

  var body: some View {
    GlassGroup {
      HStack(spacing: GlassMetrics.gap) {
        GlassIconButton(symbol: "face.smiling", label: "How are you?") {}
        GlassIconButton(symbol: "tray", label: "Inbox", badge: .count(3)) {}
        Spacer()
        HStack(spacing: Space.xs) {
          CoinIcon(size: 20)
          Text("240").font(.nookiHeadline.monospacedDigit())
        }
        .foregroundStyle(Ink.glassGlyph)
        .padding(.horizontal, Space.m)
        .frame(height: Size.control)
        .glass(.capsule, role: .control)
      }
      .padding(Space.l)
      .overlay(alignment: .bottom) {
        GlassSegmented(
          [("Room", "Room"), ("City", "City")], selection: $room, identifier: "catalog"
        )
        .padding(.bottom, Space.l)
      }
    }
    .frame(height: 220, alignment: .top)
    .frame(maxWidth: .infinity)
    .background(RoomBackdrop())
  }
}

#Preview("Catalog") {
  BothSchemes { Catalog() }
}

#Preview("Header over the room") {
  BothSchemes { HeaderOverRoom() }
}
