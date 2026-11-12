import Design
import MomentsInterface
import Pet
import WidgetInterface
import WidgetUI
import SwiftUI
import UsInterface

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
                Text("Large title").font(.ourioLargeTitle).rowCell()
                Text("Title").font(.ourioTitle).rowCell()
                Text("Headline").font(.ourioHeadline).rowCell()
                Text("Body").font(.ourioBody).rowCell()
                Text("Caption").font(.ourioCaption).foregroundStyle(Ink.textSecondary).rowCell()
            }
            VStack(spacing: Space.m) {
                PrimaryButton("Primary", symbol: "heart.fill") {}
                PrimaryButton("Disabled primary") {}.disabled(true)
                SecondaryButton("Secondary") {}
                RetryButton {}
            }
            GroupedSection(header: "Rows") {
                Row("Opens a screen", symbol: "person.2.fill", tint: UsTint.sky.color) { RowChevron() }
                ToggleRow("A switch", symbol: "hand.tap.fill", isOn: $isOn)
                Row("Erase all data", symbol: "trash.fill", tint: UsTint.coral.color, destructive: true)
                Row("Not connected", symbol: "icloud.slash", tint: UsTint.coral.color) { RetryButton(compact: true) {} }
            }
            GroupedSection(header: "Status rows", inset: StatusRow.inset) {
                StatusRow("Food", state: "Hungry", symbol: "fork.knife", emphasis: .raised, action: "Feed") {}
                StatusRow("Rest", state: "Wide awake", symbol: "moon.zzz.fill", note: CatPronouns.unchosen.say(.napsOnOwn))
                StatusRow("Love", state: "Adored", symbol: "heart.fill", tint: .blushPink, action: "Pet") {}
            }
            ItemGrid {
                GaugeTile("Full", state: "Hungry", hint: "Would love a meal", value: 0.3, symbol: "fork.knife",
                          emphasis: .raised, action: "Feed") {}
                GaugeTile("Rested", state: "Wide awake", hint: "Fine for today", value: 0.9, symbol: "moon.zzz.fill",
                          tint: .lilac, note: CatPronouns.unchosen.say(.napsOnOwn))
            }
            MomentStrip([
                StripMoment(id: "1", symbol: "moon.zzz.fill", tint: .lilac, title: "Slept", time: "till 7"),
                StripMoment(id: "2", symbol: "fork.knife", tint: .honey, title: "Ate", time: "8:12"),
                StripMoment(id: "3", symbol: "heart.fill", tint: .blushPink, title: "Cuddles", time: "12:40"),
            ])
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
            GroupedSection(header: "Stamps and seals", inset: Space.l) {
                HStack {
                    ForEach(StampArt.allCases, id: \.self) { PostageStamp($0, pinned: true) }
                }
                .rowCell()
                HStack(alignment: .bottom, spacing: Space.m) {
                    PostageStamp(.paw, size: .small)
                    PostageStamp(.moon, rare: true, pinned: true)
                    PostageStamp(.heart, size: .large, postmark: .now, pinned: true)
                    PostageStamp(.bloom, size: .large, rare: true, pinned: true)
                }
                .rowCell()
                HStack {
                    ForEach(SealArt.allCases, id: \.self) { WaxSeal($0, size: 36) }
                }
                .rowCell()
            }
            Card {
                HStack {
                    GlassIconButton(label: "Mood", action: {}) { MoodArt(mood: nil, size: 30) }
                    GlassIconButton(symbol: "tray", label: "Inbox", badge: .dot) {}
                    Spacer()
                    Design.PriceButton(120) {}
                }
            }
            GroupedSection(header: "States", inset: Space.l) {
                EmptyState(symbol: "photo.on.rectangle", title: "No moments yet", text: "Your first photo together will live here.") {
                    PrimaryButton("Add a moment", fullWidth: false) {}
                }
                LoadingState("Loading the Inbox")
                ErrorState("Couldn't load the Inbox", text: "Check your connection and try again.") {}
            }
            Callout(symbol: "hand.wave.fill", title: "Say hi to Mochi", message: CatPronouns.unchosen.say(.tapToPet), close: {})
                .calloutBubble(pointer: CalloutPointer(edge: .top, position: 0.3))
            Card(state: .selected) {
                CardHeader("Selected", detail: "A honey ring in place of the highlight edge", symbol: "checkmark",
                           opens: false)
            }
            Card(state: .disabled) {
                Text("Disabled").font(.ourioHeadline).foregroundStyle(Ink.disabledText)
            }
            PosterCard("Who knows who", status: "Your turn", emphasis: true, action: {}) {
                GamePoster(game: .whoKnows)
            }
            Toast {
                Label("Added to Moments", systemImage: "checkmark.circle.fill")
                    .font(.ourioCallout)
                    .foregroundStyle(Ink.text)
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
            Text(name).font(.ourioCallout).foregroundStyle(Ink.text)
        }
        .rowCell()
    }
}
