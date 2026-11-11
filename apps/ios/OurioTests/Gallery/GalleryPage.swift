import Design
import Pet
import RoomInterface
import SwiftUI
@testable import Billet

/// One page per family of design components, each in its usual states. A new public component gets a place on one.
enum GalleryPage: String, CaseIterable, Sendable {
    case buttons
    case labels
    case cards
    case rows
    case status
    case gauges
    case mochi
    case postage
    case tiles
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
            case .gauges: Self.gaugesPage
            case .mochi: Self.mochiPage
            case .postage: Self.postagePage
            case .tiles: Self.tilesPage
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
        Card(state: .selected) {
            CardHeader("Friday evening", detail: "Selected", symbol: "checkmark", opens: false)
        }
        Card(state: .disabled) {
            Text("Booked by someone else").font(.ourioHeadline).foregroundStyle(Ink.disabledText)
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

    /// The ring round an avatar, the bars, the four tiles with one raised and one with a note, and a day's strip.
    @MainActor @ViewBuilder private static var gaugesPage: some View {
        HStack(spacing: Space.l) {
            Circle().fill(Ink.surfaceRaised)
                .frame(width: Size.button + Space.m, height: Size.button + Space.m)
                .overlay {
                    SegmentedRing([
                        .init(value: 0.3, tint: .honey), .init(value: 0.9, tint: .lilac),
                        .init(value: 0.75, tint: .blushPink), .init(value: 0.55, tint: .sage),
                    ])
                }
            VStack(spacing: Space.s) {
                MeterBar(value: 0.4)
                MeterBar(value: 0.02, tint: .lilac)
                MeterBar(value: 1, tint: .sage)
            }
        }
        ItemGrid {
            GaugeTile("Full", state: "Hungry", hint: "Would love a meal", value: 0.3, symbol: "fork.knife",
                      emphasis: .raised, action: "Feed") {}
            GaugeTile("Rested", state: "Wide awake", hint: "Fine for today", value: 0.9, symbol: "moon.zzz.fill",
                      tint: .lilac, note: "Naps on her own")
            GaugeTile("Playful", state: "Curious", hint: "Bored in about 4 h", value: 0.55,
                      symbol: "tennisball.fill", tint: .sage, action: "Play") {}
            GaugeTile("Loved", state: "Adored", hint: "Lonely in about 9 h", value: 0.75, symbol: "heart.fill",
                      tint: .blushPink, action: "Pet") {}
        }
        MomentStrip([
            StripMoment(id: "1", symbol: "moon.zzz.fill", tint: .lilac, title: "Slept", time: "till 7 AM"),
            StripMoment(id: "2", symbol: "fork.knife", tint: .honey, title: "Ate", time: "8:12 AM"),
            StripMoment(id: "3", symbol: "binoculars.fill", tint: .sage, title: "Watched", time: "10 AM"),
            StripMoment(id: "4", symbol: "heart.fill", tint: .blushPink, title: "Cuddles", time: "12:40 PM"),
        ])
    }

    /// Mochi's whole sheet with a fixed cat: one need raised, a day of six moments, an Explorer.
    @MainActor @ViewBuilder private static var mochiPage: some View {
        MochiSheetContent(name: "Mochi", status: mochi, level: 2, progress: 0.4, days: 2, zone: .gmt, care: { _ in }) {
            PetPortrait(size: 88)
        } extraCare: {
            FlowRow {
                PillButton("Water", symbol: "drop.fill") {}
                PillButton("Brush", symbol: "paintbrush.fill") {}
                PillButton("Treat", symbol: "gift.fill") {}
            }
        }
    }

    private static let mochi: CatStatus = {
        // 04:00 UTC on 10 November 2026, the start of her day.
        let dawn = 1_794_283_200.0
        func hour(_ hour: Double) -> Double { dawn + (hour - 4) * 3600 }
        return CatStatus(
            needs: PetNeeds(full: 0.3, rested: 0.9, loved: 0.75, playful: 0.55), mind: .napping,
            about: CatAbout(
                temperament: .explorer, personality: CatTemperament.explorer.archetype, favourite: .window,
                day: [
                    CatDayMoment(kind: .slept, at: hour(4), until: hour(7), exact: false),
                    CatDayMoment(kind: .ate, at: hour(8.2), exact: true),
                    CatDayMoment(kind: .watched, at: hour(10), until: hour(11), exact: false),
                    CatDayMoment(kind: .petted, at: hour(12.7), exact: true),
                    CatDayMoment(kind: .napped, at: hour(14), until: hour(16), exact: false),
                    CatDayMoment(kind: .playedTogether, at: hour(18.1), exact: true),
                ]))
    }()

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

    /// A screen's few big actions, a ring toward a goal, and two posters of a shelf side by side.
    @MainActor @ViewBuilder private static var tilesPage: some View {
        ActionTiles([
            ActionTile("Dates", status: "3 matches", symbol: "heart.fill", tint: .blushPink) {},
            ActionTile("Wishes", status: "5 wishes", symbol: "gift.fill", tint: .honey) {},
            ActionTile("Calendar", status: "In 12 days", symbol: "calendar", tint: .teal) {},
        ])
        // Side by side while they fit, stacked at accessibility sizes as the Us screen does.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.l) { rings }
            VStack(alignment: .leading, spacing: Space.l) { rings }
        }
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Space.m) { posters }
            VStack(spacing: Space.m) { posters }
        }
    }

    @MainActor @ViewBuilder private static var rings: some View {
        ProgressRing(value: 0) { Text("0").font(.ourioTitle) }
        ProgressRing(value: 5.0 / 7) { Text("5").font(.ourioTitle) }
    }

    @MainActor @ViewBuilder private static var posters: some View {
        PosterCard("Who knows who", status: "Your turn", emphasis: true, action: {}) {
            GamePoster(game: .whoKnows, coat: .grey)
        }
        .frame(minWidth: 150)
        PosterCard("Draw & guess", status: "Played yesterday", action: {}) {
            GamePoster(game: .drawGuess, coat: .grey)
        }
        .frame(minWidth: 150)
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
                ItemCard(name, tag: ItemTag("Legendary", color: Ink.rarityLegendary.tint), open: {}) {
                    Ink.surfaceRaised.corners(.inner)
                } leadingBadge: {
                    EmptyView()
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
