import Design
import DrawInterface
import MoodInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import UIKit
import WidgetKit

// The Home Screen family: one idea per widget, each a clay object on warm paper. Honey is spent once per widget.
// Shared by the extension and the app, which draws the same views live in Settings, so nothing here may need WidgetKit
// to run.

// MARK: - Ground

extension View {
    /// Warm paper under the widget; tinted and clear Home Screens draw the system's own ground instead.
    func familyGround() -> some View {
        modifier(FamilyGround()).widgetTypeCap()
    }
}

/// The ground a widget is laid on: the app's own screen colour, flat, so the cards on it read as the app's cards do.
struct FamilyGroundFill: View {
    var body: some View { Ink.screen }
}

private struct FamilyGround: ViewModifier {
    @Environment(\.widgetRenderingMode) private var mode

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            if mode == .fullColor { FamilyGroundFill() } else { Color.clear }
        }
    }
}

// MARK: - Pieces

/// Clay and wells come from the design kit; the tinted and clear Home Screens redraw everything in one tint, where a
/// slab would turn into a flat block, so they get the bare content on the system's own ground.
private struct WidgetSlab: ViewModifier {
    @Environment(\.widgetRenderingMode) private var mode

    func body(content: Content) -> some View {
        if mode == .fullColor { content.cardSurface() } else { content }
    }
}

private struct WidgetWell: ViewModifier {
    @Environment(\.widgetRenderingMode) private var mode

    func body(content: Content) -> some View {
        if mode == .fullColor { content.wellSurface() } else { content.corners(.inner) }
    }
}

extension View {
    fileprivate func slab() -> some View { modifier(WidgetSlab()) }
    fileprivate func well() -> some View { modifier(WidgetWell()) }
}

/// Widths and gaps every family lays out with, so a widget's edge reads the same in each size.
private enum Edge {
    /// The widget's own margin: a small widget has less to spare.
    static func margin(_ family: WidgetFamily) -> CGFloat { family == .systemSmall ? Space.m : Space.l }
}

/// The one honey control of a widget that has one: what Mochi needs most, a meal when she is hungry, a pet otherwise.
private struct CareButton: View {
    let care: MochiPose.Care
    let catName: String
    /// Only the glyph, for the small widget.
    var compact = false
    /// Takes the width it is given, so the row it ends is one bar.
    var fills = false

    var body: some View {
        Group {
            if care == .feed {
                Button(intent: FeedMochiIntent()) { label }
            } else {
                Button(intent: PetMochiIntent()) { label }
            }
        }
        .buttonStyle(PressScaleStyle())
        .widgetAccentable()
        .accessibilityLabel(care == .feed ? "Feed \(catName)" : "Pet \(catName)")
    }

    private var symbol: String { care == .feed ? "fork.knife" : "pawprint.fill" }

    @ViewBuilder
    private var label: some View {
        if compact {
            Image(systemName: symbol)
                .font(.ourioHeadline)
                .foregroundStyle(Ink.heroInk)
                .frame(width: Size.control, height: Size.control)
                .background(Color.honey, in: .circle)
        } else {
            ViewThatFits(in: .horizontal) {
                Label(care == .feed ? "Feed" : "Pet", systemImage: symbol).lineLimit(1)
                Image(systemName: symbol)
            }
                .font(.ourioHeadline)
                .foregroundStyle(Ink.heroInk)
                .padding(.horizontal, Space.m)
                .frame(maxWidth: fills ? .infinity : nil)
                .frame(height: Size.control)
                .background(Color.honey, in: .capsule)
        }
    }
}

/// A quiet second button beside the care button: a hug for the partner, filled once it is sent today. The same height
/// as the care button and flat, so the two sit on one line.
private struct HugButton: View {
    let sent: Bool
    let partner: String

    var body: some View {
        Button(intent: SendHugIntent()) {
            Image(systemName: sent ? "heart.fill" : "heart")
                .font(.ourioHeadline)
                .foregroundStyle(sent ? Color.blushPink : Ink.text)
                .frame(width: Size.control, height: Size.control)
                .background(Ink.surfaceRaised, in: .circle)
        }
        .buttonStyle(PressScaleStyle())
        .widgetAccentable(sent)
        .accessibilityLabel(sent ? "Hug sent to \(partner)" : "Send \(partner) a hug")
    }
}

/// The care button and the hug, one row of one height.
private struct CareRow: View {
    let pose: MochiPose
    let snapshot: OurioSnapshot
    var hugs = true

    var body: some View {
        HStack(spacing: Space.s) {
            CareButton(care: pose.care, catName: snapshot.catName, fills: true)
            if hugs { HugButton(sent: HugState.sent(snapshot), partner: snapshot.partner) }
        }
    }
}

/// The whole widget is the tap target, so this says so in plain words rather than drawing a button.
private struct ReplyLine: View {
    var body: some View {
        Text("Tap to reply")
            .font(.ourioMicro)
            .foregroundStyle(Ink.textSecondary)
            .lineLimit(1)
    }
}

private struct LevelChip: View {
    let level: Int

    var body: some View {
        Chip("Lv \(level)", style: .quiet)
            .monospacedDigit()
            .accessibilityLabel("Level \(level)")
    }
}

/// What she says, on a small flat label beside her: no shadow, since a blur on a label this small reads as a smudge.
private struct SpeechBubble: View {
    let text: String
    var font: Font = .ourioMicro
    var lines = 1
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(Ink.text)
            .lineLimit(lines)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(mode == .fullColor ? Ink.surfaceRaised : Ink.text.opacity(0.14), in: .capsule)
            .accessibilityHidden(true)
    }
}

/// Her empty bowl, when she is hungry: a small clay prop at her feet.
private struct Bowl: View {
    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: Space.m, bottomTrailingRadius: Space.m)
                .fill(Color.honeyDeep)
                .frame(width: 40, height: 18)
                .offset(y: 7)
            Ellipse().fill(Color.honey).frame(width: 44, height: 14)
            Ellipse().fill(Ink.surfaceRaised).frame(width: 34, height: 9).offset(y: Space.xxs)
        }
        .frame(width: 44, height: 26)
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}

/// Mochi in her well. Her portrait is a bust whose lower edge is a straight cut, so it fades out into the well instead
/// of ending on a line, and it sits clear of the controls. Her state shows as a prop and a word, not as a different cat.
private struct MochiStage: View {
    enum Layout {
        /// The speech on its own line above her: for a well that is about as tall as it is wide.
        case stacked
        /// The speech in the corner beside her: for a well that is much wider than tall.
        case wide
    }

    enum Actions {
        case none
        /// The care button on the well's corner, for the small widget.
        case corner
        /// The care button and the hug in a row along the well's foot, below her.
        case shelf
    }

    let entry: FamilyEntry
    var layout = Layout.stacked
    var showsSpeech = true
    var speechFont: Font = .ourioMicro
    var actions = Actions.none

    private var s: OurioSnapshot { entry.snapshot }
    private var pose: MochiPose { entry.pose }
    private var speech: String { pose.speech(s, drawing: entry.facts.drawing) }

    /// What the controls take along the well's foot.
    private var foot: CGFloat { actions == .shelf ? Size.control + Space.s * 2 : Space.xs }

    var body: some View {
        content
            .padding(.bottom, foot)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if actions == .shelf {
                    CareRow(pose: pose, snapshot: s).padding(Space.s)
                }
            }
            .overlay(alignment: .bottomLeading) { prop }
            .overlay(alignment: .bottomTrailing) { corner }
            .well()
            .corners(.inner)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(s.catName), \(pose.word.lowercased())")
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .stacked:
            VStack(spacing: Space.xs) {
                if showsSpeech { speechRow }
                portrait.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .padding([.top, .horizontal], Space.s)
        case .wide:
            portrait
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if showsSpeech { SpeechBubble(text: speech, font: speechFont, lines: 2).frame(maxWidth: Size.row + Space.m, alignment: .leading) }
                }
                .padding([.top, .horizontal], Space.s)
        }
    }

    /// The speech on one line, or two when the well is narrow.
    private var speechRow: some View {
        ViewThatFits(in: .horizontal) {
            SpeechBubble(text: speech, font: speechFont).fixedSize().frame(maxWidth: .infinity, alignment: .leading)
            SpeechBubble(text: speech, font: speechFont, lines: 2).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Her bowl stands at one fixed corner.
    @ViewBuilder
    private var prop: some View {
        if pose == .hungry {
            Bowl().padding(.leading, Space.s).padding(.bottom, foot)
        }
    }

    @ViewBuilder
    private var corner: some View {
        if actions == .corner {
            CareButton(care: pose.care, catName: s.catName, compact: true).padding(Space.xs)
        }
    }

    @ViewBuilder
    private var portrait: some View {
        Group {
            if let image = UIImage(named: s.catAvatar) ?? UIImage(named: "MochiPortrait") {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .widgetAccentedRenderingMode(.accented)
                    .scaledToFit()
                    .mask(alignment: .bottom) {
                        LinearGradient(stops: [.init(color: .black, location: 0.72), .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            } else {
                Image(systemName: "cat.fill").resizable().scaledToFit().foregroundStyle(Ink.textSecondary)
            }
        }
        .opacity(pose == .asleep ? 0.8 : 1)
    }
}

/// A bar with its fill drawn at a measured width: the kit's bar scales its fill, which a widget's snapshot can leave empty.
private struct FilledBar: View {
    let fraction: Double

    var body: some View {
        Capsule()
            .fill(Ink.well)
            .frame(height: Space.s)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Ink.accentText)
                        .frame(width: max(Space.s, geo.size.width * min(max(fraction, 0), 1)))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

/// A card with a mark, one line of words and a bar: the streak and the next date share it, so two of them in a column
/// have the same height and the same padding.
private struct InfoTile: View {
    let mark: AnyView
    let title: String
    let caption: String
    var captionIsUrgent = false
    let progress: Double

    var body: some View {
        HStack(spacing: Space.m) {
            mark.frame(width: Size.tileMark, height: Size.tileMark)
            VStack(alignment: .leading, spacing: Space.xs) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        titleText
                        Spacer(minLength: 0)
                        captionText
                    }
                    titleText.frame(maxWidth: .infinity, alignment: .leading)
                }
                FilledBar(fraction: progress).widgetAccentable()
            }
        }
        .padding(Space.m)
        .slab()
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        Text(title).font(.ourioHeadline).monospacedDigit().foregroundStyle(Ink.text).lineLimit(1)
    }

    private var captionText: some View {
        Text(caption)
            .font(.ourioMicro)
            .foregroundStyle(captionIsUrgent ? Ink.accentText : Ink.textSecondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// The flame: the streak's number, a bar to the next milestone, and a word when today still counts.
private struct StreakTile: View {
    let glance: StreakGlance

    var body: some View {
        InfoTile(
            mark: AnyView(
                Image(systemName: "flame.fill")
                    .font(.ourioTitle)
                    .foregroundStyle(glance.status == .cold ? Ink.textTertiary : Color.honey)
                    .widgetAccentable()),
            title: glance.count > 0 ? "Day \(glance.count)" : "No streak",
            caption: glance.caption, captionIsUrgent: glance.isAtRisk, progress: glance.progress)
    }
}

// MARK: - Mochi

struct MochiFamilyView: View {
    let entry: FamilyEntry
    let family: WidgetFamily
    /// Inside the Our day widget, where the care button is the one honey mark.
    var calm = false

    private var s: OurioSnapshot { entry.snapshot }
    private var pose: MochiPose { entry.pose }
    private var line: String { pose.line(s, drawing: entry.facts.drawing) }
    private var streak: StreakGlance { StreakGlance(entry.facts.streak, on: s.date) }

    var body: some View {
        Group {
            switch family {
            case .systemMedium: medium
            case .systemLarge: large
            default: small
            }
        }
        .widgetURL(DeepLink.room.url)
    }

    private var small: some View {
        MochiStage(entry: entry, actions: .corner)
            .padding(Space.s)
    }

    /// The well on the left, a column of words and the buttons on the right.
    private var medium: some View {
        HStack(spacing: Space.m) {
            MochiStage(entry: entry, showsSpeech: false)
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Text(pose.word).font(.ourioTitle).foregroundStyle(Ink.text).lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    if !calm { LevelChip(level: entry.facts.wallet.level) }
                }
                SpeechBubble(text: pose.speech(s, drawing: entry.facts.drawing), font: .ourioMicro)
                Spacer(minLength: Space.xs)
                CareRow(pose: pose, snapshot: s, hugs: !calm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(Edge.margin(.systemMedium))
    }

    /// The least the well may be for the cat to show above the shelf; a screen too short for it loses the streak.
    private static let stageHeight: CGFloat = 170

    private var stage: some View {
        MochiStage(entry: entry, layout: .wide, speechFont: .ourioMicro, actions: .shelf)
    }

    private var largeHeader: some View {
        HStack(alignment: .center, spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(pose.word).font(.ourioLargeTitle).foregroundStyle(Ink.text).lineLimit(1).minimumScaleFactor(0.7)
                Text(line).font(.ourioCaption).foregroundStyle(Ink.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            LevelChip(level: entry.facts.wallet.level)
        }
    }

    private var large: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: Space.m) {
                largeHeader
                stage.frame(minHeight: Self.stageHeight, idealHeight: Self.stageHeight, maxHeight: .infinity)
                StreakTile(glance: streak)
            }
            .padding(Edge.margin(.systemLarge))
            VStack(spacing: Space.m) {
                largeHeader
                stage
            }
            .padding(Edge.margin(.systemLarge))
        }
    }
}

// MARK: - Us

struct UsFamilyView: View {
    let entry: FamilyEntry
    let family: WidgetFamily
    var calm = false

    private var s: OurioSnapshot { entry.snapshot }
    private var streak: StreakGlance { StreakGlance(entry.facts.streak, on: s.date) }

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: Space.m) {
                days.frame(maxWidth: .infinity)
                nextTile
            }
            .padding(Edge.margin(family))
        case .systemLarge:
            VStack(spacing: Space.m) {
                days.frame(maxWidth: .infinity, maxHeight: .infinity)
                nextRow
                StreakTile(glance: streak)
            }
            .padding(Edge.margin(family))
        default:
            days.frame(maxWidth: .infinity, maxHeight: .infinity).padding(Edge.margin(family))
        }
    }

    private var days: some View {
        VStack(spacing: 0) {
            if !calm {
                Image(systemName: "heart.fill").font(.ourioHeadline).foregroundStyle(Color.blushPink).widgetAccentable()
            }
            Text("\(s.daysTogether)")
                .font(.ourioNumber)
                .monospacedDigit()
                .foregroundStyle(calm ? Ink.text : Ink.accentText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
            Text(s.daysTogether == 1 ? "day together" : "days together")
                .font(.ourioCaption)
                .foregroundStyle(Ink.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// How close the next date is: a bar that fills over the last month before it.
    static let countdownDays = 30

    private func caption(_ next: OurioSnapshot.NextEvent) -> String {
        next.daysLeft == 0 ? "Today" : "in \(next.daysLeft) \(next.daysLeft == 1 ? "day" : "days")"
    }

    private func countdown(_ next: OurioSnapshot.NextEvent) -> Double {
        Double(Self.countdownDays - min(next.daysLeft, Self.countdownDays)) / Double(Self.countdownDays)
    }

    /// The next date as a row, the same card as the streak under it.
    @ViewBuilder
    private var nextRow: some View {
        if let next = s.next {
            InfoTile(
                mark: AnyView(RowIcon(symbol: next.icon.symbol, tint: .honey, size: Size.tileMark, style: .clay).widgetAccentable()),
                title: next.title, caption: caption(next), progress: countdown(next))
        } else {
            Text("Add a date in Us")
                .font(.ourioHeadline)
                .foregroundStyle(Ink.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(Space.m)
                .slab()
        }
    }

    /// The next date as a column beside the days: its icon drops first when the title takes two lines.
    @ViewBuilder
    private var nextTile: some View {
        Group {
            if let next = s.next {
                ViewThatFits(in: .vertical) {
                    nextColumn(next, icon: true)
                    nextColumn(next, icon: false)
                }
            } else {
                Text("Add a date in Us").font(.ourioHeadline).foregroundStyle(Ink.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .padding(Space.m)
        .frame(maxHeight: .infinity)
        .slab()
    }

    private func nextColumn(_ next: OurioSnapshot.NextEvent, icon: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if icon {
                RowIcon(symbol: next.icon.symbol, tint: .honey, size: Size.tileMark, style: .clay).widgetAccentable()
            }
            Spacer(minLength: 0)
            Text(next.title).font(.ourioHeadline).foregroundStyle(Ink.text).lineLimit(2)
            Text(caption(next)).font(.ourioCaption).foregroundStyle(Ink.textSecondary).lineLimit(1)
            FilledBar(fraction: countdown(next)).widgetAccentable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Partner

struct PartnerFamilyView: View {
    let entry: FamilyEntry
    let family: WidgetFamily

    private var s: OurioSnapshot { entry.snapshot }
    private var news: PartnerNews? { PartnerNews.latest(s, drawing: entry.facts.drawing) }

    var body: some View {
        if family == .systemMedium {
            HStack(spacing: Space.l) {
                card.aspectRatio(1, contentMode: .fit)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(headline).font(.ourioTitle).foregroundStyle(Ink.text).lineLimit(2).minimumScaleFactor(0.75)
                    if let news {
                        Text(news.sentLabel(relativeTo: s.date)).font(.ourioCaption).foregroundStyle(Ink.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: Space.s) {
                        HugButton(sent: HugState.sent(s), partner: s.partner)
                        ReplyLine()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .privacySensitive()
            }
            .padding(Edge.margin(family))
        } else {
            VStack(spacing: Space.s) {
                card.frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: Space.xxs) {
                    Text("From \(s.partner)").font(.ourioHeadline).foregroundStyle(Ink.text).lineLimit(1)
                    if news != nil { ReplyLine() }
                }
            }
            .padding(Edge.margin(family))
        }
    }

    private var headline: String {
        switch news {
        case .drawing: "\(s.partner) drew you something"
        case .mood(let check): "\(s.partner) is \(check.mood.title.lowercased())"
        case nil: "Nothing from \(s.partner) yet"
        }
    }

    /// A small print of what they sent, on paper, with a stamp on its corner.
    private var card: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
                .fill(Ink.paper)
                .overlay { RoundedRectangle(cornerRadius: Radius.inner, style: .continuous).stroke(Ink.paperEdge, lineWidth: 1) }
            content.padding(Space.s).frame(maxWidth: .infinity, maxHeight: .infinity)
            PostageStamp(.heart, size: .regular)
                .rotationEffect(.degrees(6))
                .padding(Space.xs)
        }
        .accessibilityHidden(news == nil)
    }

    @ViewBuilder
    private var content: some View {
        switch news {
        case .drawing(let drawing):
            DrawingCard(strokes: drawing.strokes, wallpaper: LockWallpaper(paper: drawing.paper), margin: 0.08)
                .clipShape(RoundedRectangle(cornerRadius: Radius.inner - Space.s, style: .continuous))
                .privacySensitive()
        case .mood(let check):
            MoodArt(mood: check.mood, size: 64).privacySensitive()
        case nil:
            Image(systemName: "envelope").font(.ourioTitle).foregroundStyle(Ink.textTertiary)
        }
    }
}

// MARK: - Coins

struct CoinsFamilyView: View {
    let entry: FamilyEntry
    let family: WidgetFamily

    private var glance: CoinsGlance { CoinsGlance(entry.facts.wallet) }

    var body: some View {
        if family == .systemMedium {
            HStack(spacing: Space.m) {
                balance.frame(maxWidth: .infinity, alignment: .leading)
                levelTile
            }
            .padding(Edge.margin(family))
        } else {
            balance.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(Edge.margin(family))
        }
    }

    private var balance: some View {
        ViewThatFits(in: .vertical) {
            balanceColumn(icon: true, lines: 2)
            balanceColumn(icon: true, lines: 1)
            balanceColumn(icon: false, lines: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(glance.coins) coins")
    }

    private func balanceColumn(icon: Bool, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if icon { CoinIcon(size: Size.tileMark).widgetAccentable() }
            Spacer(minLength: 0)
            Text(glance.coins.formatted())
                .font(.ourioNumber)
                .monospacedDigit()
                .foregroundStyle(Ink.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(glance.caption).font(.ourioCaption).foregroundStyle(Ink.textSecondary).lineLimit(lines)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var levelTile: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Care level").font(.ourioMicro).foregroundStyle(Ink.textSecondary)
            Text("Lv \(glance.level)").font(.ourioTitle).monospacedDigit().foregroundStyle(Ink.accentText).widgetAccentable()
            FilledBar(fraction: glance.progress).widgetAccentable()
            Text("\(Int((glance.progress * 100).rounded()))% to Lv \(glance.level + 1)")
                .font(.ourioMicro)
                .foregroundStyle(Ink.textSecondary)
        }
        .frame(width: 124, alignment: .leading)
        .padding(Space.m)
        .frame(maxHeight: .infinity)
        .slab()
    }
}

// MARK: - Memory

struct MemoryFamilyView: View {
    let entry: FamilyEntry
    let family: WidgetFamily

    private var photo: UIImage? { entry.momentImage.flatMap(UIImage.init(data:)) }
    private var caption: String { entry.snapshot.moment?.caption ?? "" }

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: Space.l) {
                print.frame(width: 140)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(caption.isEmpty ? "A moment together" : caption)
                        .font(.ourioTitle).foregroundStyle(Ink.text).lineLimit(3).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .privacySensitive()
            }
            .padding(Edge.margin(family))
        case .systemLarge:
            print.padding(Edge.margin(family))
        default:
            print.padding(Edge.margin(family))
        }
    }

    /// A polaroid: the photo square on white paper, the date in the wide border, a stamp over the corner.
    private var print: some View {
        VStack(spacing: Space.s) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .widgetAccentedRenderingMode(.desaturated)
                            .scaledToFill()
                            .privacySensitive()
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.ourioTitle)
                            .foregroundStyle(Ink.textTertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .well()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Space.xs, style: .continuous))
            Text(label)
                .font(.ourioMicro)
                .foregroundStyle(Ink.heroInk)
                .lineLimit(1)
        }
        .padding([.horizontal, .top], Space.s)
        .padding(.bottom, Space.s)
        .background(Ink.paper, in: RoundedRectangle(cornerRadius: Space.s, style: .continuous))
        .overlay(alignment: .topTrailing) {
            PostageStamp(.paw, size: .regular).rotationEffect(.degrees(8)).padding(Space.s)
        }
        .rotationEffect(.degrees(-2))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var label: String {
        if photo == nil { return "Pin a moment in Ourio" }
        guard let date = entry.momentDate else { return caption }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

// MARK: - Our day

struct DayFamilyView: View {
    let entry: FamilyEntry
    var family: WidgetFamily = .systemLarge

    var body: some View {
        VStack(spacing: 0) {
            MochiFamilyView(entry: entry, family: .systemMedium, calm: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 0) {
                Link(destination: DeepLink.calendar.url) { UsFamilyView(entry: entry, family: .systemSmall, calm: true) }
                Link(destination: DeepLink.inbox.url) { PartnerFamilyView(entry: entry, family: .systemSmall) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
