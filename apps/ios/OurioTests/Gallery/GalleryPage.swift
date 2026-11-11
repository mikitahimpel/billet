import Design
import SwiftUI

/// One page per family of design components, each in its usual states. A new public component gets a place on one.
enum GalleryPage: String, CaseIterable, Sendable {
    case buttons
    case labels
    case cards
    case rows
    case status
    case postage
    case fields
    case grid
    case callout
    case screen

    @MainActor @ViewBuilder var view: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            switch self {
            case .buttons: Self.buttonsPage
            case .labels: Self.labelsPage
            case .cards: Self.cardsPage
            case .rows: Self.rowsPage
            case .status: Self.statusPage
            case .postage: Self.postagePage
            case .fields: Self.fieldsPage
            case .grid: Self.gridPage
            case .callout: Self.calloutPage
            case .screen: Self.screenPage
            }
        }
        .padding(.horizontal, Space.gutter)
    }

    @MainActor @ViewBuilder private static var buttonsPage: some View {
        PrimaryButton("Share with Alex") {}
        PrimaryButton("Pick how you feel") {}.disabled(true)
        SecondaryButton("Place", symbol: "mappin") {}
        HStack {
            RetryButton {}
            RetryButton(compact: true) {}
        }
        HStack {
            GlassIconButton(symbol: "tray", label: "Inbox", badge: .count(3)) {}
            PriceButton(120, was: 150) {}
        }
        // A header's controls share one glass container, which draws its glass over a badge left inside it.
        GlassGroup {
            HStack(spacing: GlassMetrics.gap) {
                GlassIconButton(symbol: "tray.fill", label: "Inbox", badge: .count(2)) {}
                GlassIconButton(symbol: "bell", label: "Alerts", badge: .dot) {}
                GlassIconButton(symbol: "tray.fill", label: "Inbox", badge: .count(12)) {}
            }
        }
        ActionRow {
            SecondaryButton("Later", fullWidth: false) {}
            PrimaryButton("Answer now", fullWidth: false) {}
        }
    }

    @MainActor @ViewBuilder private static var labelsPage: some View {
        SectionHeader("Daily deals", symbol: "tag.fill") { Text("New at midnight") }
        FlowRow {
            Chip("Rare", style: .tinted(.teal))
            Chip("−20%", style: .honey)
            Chip("Owned", symbol: "checkmark")
            Chip("For the window", style: .quiet)
            Chip("New", style: .honey)
        }
        HStack {
            FilterChip("Today", isSelected: true) {}
            FilterChip("Cats", isSelected: false) {}
        }
        EmptyState(symbol: "tray", title: "All quiet", text: "Notes and gifts show up here.")
        ErrorState(text: "Check the connection and try again.") {}
    }

    @MainActor @ViewBuilder private static var cardsPage: some View {
        Card(warm: true) {
            CardHeader("Anniversary", detail: "In 12 days · Friday 21 November", symbol: "heart.fill")
        }
        Card {
            CardHeader("A weekend away somewhere warm", detail: "3 ideas saved", symbol: "airplane", tint: .teal)
        }
        ContentCard("Weekend in Lisbon", subtitle: "Saved by both of you", chip: Chip("Plan", style: .honey)) {
            SecondaryButton("Edit", fullWidth: false) {}
            PrimaryButton("Book it", fullWidth: false) {}
        }
        Card {
            CardActions {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cosy corner").font(.ourioHeadline).foregroundStyle(Ink.text)
                    Text("A seat, a lamp and a rug").font(.ourioCaption).foregroundStyle(Ink.textSecondary)
                }
            } trail: {
                PriceButton(240, was: 300) {}
            }
        }
    }

    @MainActor @ViewBuilder private static var rowsPage: some View {
        GroupedSection(header: "Settings", footer: "Haptics are only on this phone.") {
            Row("Profile", detail: "Mikita", symbol: "person.fill") { RowChevron() }
            ToggleRow("Haptics", symbol: "hand.tap.fill", tint: .blushPink, isOn: .constant(true))
            Row("Erase all data", symbol: "trash.fill", destructive: true)
        }
        GroupedSection(header: "Labs") {
            PickerRow("Window view", symbol: "window.casement", selection: .constant("Desk with Mochi")) {
                Text("Desk with Mochi").tag("Desk with Mochi")
                Text("Suburbia").tag("Suburbia")
            }
            PickerRow("Room lighting", symbol: "lightbulb.fill", selection: .constant("Follow the test")) {
                Text("Follow the test").tag("Follow the test")
            }
            Row("Show hints again on the next launch", symbol: "lightbulb.fill") { RowChevron() }
            ToggleRow("Streak at risk reminders", isOn: .constant(false))
        }
    }

    /// A raised row and a quiet one, a row with a note, and the badge on a round control.
    @MainActor @ViewBuilder private static var statusPage: some View {
        GroupedSection(inset: StatusRow.inset) {
            StatusRow("Water", state: "Thirsty", symbol: "drop.fill", emphasis: .raised, action: "Water") {}
            StatusRow("Light", state: "Plenty", symbol: "sun.max.fill", note: "Moves on its own")
            StatusRow("Love", state: "Wants a hug", symbol: "heart.fill", tint: .blushPink, emphasis: .raised,
                      action: "Hug") {}
            StatusRow("Food", state: "Well fed", symbol: "fork.knife", action: "Feed") {}
        }
        HStack(spacing: Space.xl) {
            GlassIconButton(symbol: "leaf.fill", label: "Plant") {}
                .overlay(alignment: .topTrailing) { SymbolBadge(symbol: "drop.fill") }
            GlassIconButton(symbol: "person.fill", label: "Alex") {}
                .overlay(alignment: .topTrailing) { SymbolBadge(symbol: "heart.fill", tint: .blushPink) }
        }
        // Glass controls sit in chrome, which caps its text size as the app's header does.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Every stamp pinned in a row, the sizes, rare foil and a postmark, beside the seals of the same family.
    @MainActor @ViewBuilder private static var postagePage: some View {
        HStack(spacing: Space.m) {
            ForEach(StampArt.allCases, id: \.self) { PostageStamp($0, pinned: true) }
        }
        HStack(alignment: .bottom, spacing: Space.l) {
            PostageStamp(.paw, size: .small)
            PostageStamp(.moon, rare: true, pinned: true)
            PostageStamp(.heart, size: .large, postmark: Date(timeIntervalSince1970: 1_762_776_000), pinned: true)
            PostageStamp(.bloom, size: .large, rare: true, pinned: true)
        }
        HStack(spacing: Space.m) {
            ForEach(SealArt.allCases, id: \.self) { WaxSeal($0, size: 36) }
        }
    }

    @MainActor @ViewBuilder private static var fieldsPage: some View {
        Field("A few words (optional)", text: .constant(""), axis: .vertical, lines: 1...3)
        FormField("Name", placeholder: "Your name", text: .constant("Mikita"), footer: "Your partner sees it.")
        HStack {
            LimitCounter(count: 12, limit: 40)
            LimitCounter(count: 34, limit: 40)
            LimitCounter(count: 40, limit: 40)
        }
        FormField("Invite code", placeholder: "Code", text: .constant("K7QM"), error: "That code isn't working.")
    }

    @MainActor @ViewBuilder private static var gridPage: some View {
        ItemGrid {
            ForEach(["Cat tower", "Window seat with a long name", "Lamp"], id: \.self) { name in
                ItemCard(name, subtitle: "Cosy in any corner", open: {}) {
                    Ink.surfaceRaised.corners(.inner)
                } leadingBadge: {
                    Chip("Legendary", style: .tinted(.orange))
                } trailingBadge: {
                    Chip("−20%", style: .honey)
                } footer: {
                    PriceButton(120, was: 150) {}
                }
            }
        }
    }

    @MainActor @ViewBuilder private static var calloutPage: some View {
        Callout(symbol: "hand.wave.fill", title: "Say hi to Mochi", message: "Tap her in the room to pet her.",
                close: {})
            .calloutBubble(pointer: CalloutPointer(edge: .bottom, position: 0.3))
    }

    /// The bottom slot of `Screen`: the primary last, the secondary over it.
    @MainActor @ViewBuilder private static var screenPage: some View {
        Color.clear
            .frame(height: Size.button * 3)
            .bottomActions {
                PrimaryButton("Continue") {}
            } secondary: {
                SecondaryButton("Skip for now") {}
            }
    }
}
