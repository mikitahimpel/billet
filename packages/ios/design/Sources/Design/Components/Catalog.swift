import SwiftUI

private struct Catalog: View {
  @State private var room = "Room"
  @State private var isOn = true
  @State private var note = ""

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
              RoundedRectangle(cornerRadius: Radius.inner).fill(color).frame(height: 36)
                .overlay(RoundedRectangle(cornerRadius: Radius.inner).strokeBorder(Ink.separator))
              Text(name).font(.ourioMicro).foregroundStyle(Ink.textSecondary)
            }
          }
        }

        SectionHeader("Type")
        VStack(alignment: .leading, spacing: Space.xs) {
          Text("Large title").font(.ourioLargeTitle)
          Text("Title").font(.ourioTitle)
          Text("Headline").font(.ourioHeadline)
          Text("Body").font(.ourioBody)
          Text("Callout").font(.ourioCallout)
          Text("Caption").font(.ourioCaption)
          Text("Micro").font(.ourioMicro)
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
          ForEach([Radius.inner, Radius.control, Radius.card, Radius.sheet], id: \.self) {
            RoundedRectangle(cornerRadius: $0).fill(Ink.surfaceRaised).frame(width: 40, height: 40)
          }
        }

        SectionHeader("Buttons and fields")
        Field("A few words (optional)", text: $note, axis: .vertical, lines: 1...3)
        PrimaryButton("Share with Alex") {}
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

        SectionHeader("Stamps and seals")
        HStack {
          ForEach(StampArt.allCases, id: \.self) { PostageStamp($0, width: 32) }
        }
        HStack {
          ForEach(SealArt.allCases, id: \.self) { WaxSeal($0, size: 36) }
        }

        SectionHeader("Rows")
        GroupedSection(header: "Settings", footer: "Haptics are only on this phone.") {
          Row("Profile", detail: "Mikita", symbol: "person.fill") { RowChevron() }
          ToggleRow("Haptics", symbol: "hand.tap.fill", tint: .blushPink, isOn: $isOn)
          Row("Erase all data", symbol: "trash.fill", destructive: true)
        }
        Card(warm: true) {
          CardHeader("A hero card", detail: "Same radius, warmer", symbol: "sparkles")
        }
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
          Text("240").font(.ourioHeadline.monospacedDigit())
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
