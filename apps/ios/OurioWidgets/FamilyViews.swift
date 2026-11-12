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

/// The one honey control of a widget that has one: what Mochi needs most, a meal when she is hungry, a pet otherwise.
private struct CareButton: View {
    let care: MochiPose.Care
    let catName: String
    /// Only the glyph, for the small widget.
    var compact = false

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
            Label(care == .feed ? "Feed" : "Pet", systemImage: symbol)
                .font(.ourioCaption.weight(.bold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Ink.heroInk)
                .padding(.horizontal, Space.m)
                .frame(height: Size.control)
                .background(Color.honey, in: .capsule)
        }
    }
}

/// A quiet second button beside the care button: a hug for the partner, filled once it is sent today.
private struct HugButton: View {
    let sent: Bool
    let partner: String

    var body: some View {
        Button(intent: SendHugIntent()) {
            Image(systemName: sent ? "heart.fill" : "heart")
                .font(.ourioHeadline)
                .foregroundStyle(sent ? Color.blushPink : Ink.text)
                .frame(width: Size.control, height: Size.control)
                .slab()
        }
        .buttonStyle(PressScaleStyle())
        .widgetAccentable(sent)
        .accessibilityLabel(sent ? "Hug sent to \(partner)" : "Send \(partner) a hug")
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

/// What she says, on a small clay label beside her.
private struct SpeechBubble: View {
    let text: String
    var font: Font = .ourioMicro
    var lines = 2

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(Ink.text)
            .lineLimit(lines)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .slab()
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

/// Mochi in her well, the room's colour at night; her state shows as a mark on the well and a prop, not as a different cat.
private struct MochiStage: View {
    let entry: FamilyEntry
    var showsSpeech = true
    var speechFont: Font = .ourioMicro
    var showsWord = false
    /// The care button sits on the stage in the small widget, where there is no room for it beside.
    var carries = false
    @Environment(\.widgetRenderingMode) private var mode

    private var s: OurioSnapshot { entry.snapshot }
    private var pose: MochiPose { entry.pose }
    private var mood: PartnerMood? { PartnerNews.latest(s, drawing: entry.facts.drawing).flatMap(\.mood) }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                portrait
                    .frame(width: side * 0.78, height: side * 0.78)
                    .scaleEffect(pose == .purring ? 1.04 : 1, anchor: .bottom)
                    .opacity(pose == .asleep ? 0.8 : 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .offset(y: Space.s)
                if pose == .hungry {
                    Bowl().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(Space.s)
                }
                if showsSpeech {
                    SpeechBubble(text: pose.speech(s, drawing: entry.facts.drawing), font: speechFont)
                        .frame(maxWidth: geo.size.width * 0.72, maxHeight: .infinity, alignment: .topLeading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(Space.s)
                }
                mark.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(Space.s)
                if showsWord {
                    Chip(pose.word, style: pose == .hungry ? .honey : .quiet)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(Space.s)
                }
                if carries {
                    CareButton(care: pose.care, catName: s.catName, compact: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(Space.xs)
                }
            }
        }
        .well()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(s.catName), \(pose.word.lowercased())")
    }

    @ViewBuilder
    private var portrait: some View {
        if let image = UIImage(named: s.catAvatar) ?? UIImage(named: "MochiPortrait") {
            Image(uiImage: image)
                .resizable()
                .widgetAccentedRenderingMode(.accented)
                .scaledToFit()
        } else {
            Image(systemName: "cat.fill").resizable().scaledToFit().foregroundStyle(Ink.textSecondary)
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch pose {
        case .purring: RowIcon(symbol: "heart.fill", tint: .blushPink, size: Size.tileMark, style: .clay).widgetAccentable()
        case .asleep: RowIcon(symbol: "moon.zzz.fill", tint: .honey, size: Size.tileMark, style: .clay).widgetAccentable()
        case .hungry: EmptyView()
        case .drowsy, .napping: RowIcon(symbol: "zzz", tint: .honey, size: Size.tileMark, style: .clay).widgetAccentable()
        case .cuddly: RowIcon(symbol: "hand.raised.fill", tint: .blushPink, size: Size.tileMark, style: .clay).widgetAccentable()
        case .playful: RowIcon(symbol: "tennisball.fill", tint: .honey, size: Size.tileMark, style: .clay).widgetAccentable()
        case .waiting:
            if let mood {
                MoodArt(mood: mood, size: Size.tileMark)
            } else {
                RowIcon(symbol: "envelope.fill", tint: .honey, size: Size.tileMark, style: .clay).widgetAccentable()
            }
        case .chirpy: RowIcon(symbol: "music.note", tint: .honey, size: Size.tileMark, style: .clay).widgetAccentable()
        case .quiet, .idle: EmptyView()
        }
    }
}

/// The flame: the streak's number, a bar to the next milestone, and a word when today still counts.
private struct StreakTile: View {
    let glance: StreakGlance

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "flame.fill")
                .font(.ourioTitle)
                .foregroundStyle(glance.status == .cold ? Ink.textTertiary : Color.honey)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack {
                    Text(glance.count > 0 ? "Day \(glance.count)" : "No streak")
                        .font(.ourioHeadline)
                        .monospacedDigit()
                        .foregroundStyle(Ink.text)
                    Spacer(minLength: 0)
                    Text(glance.caption)
                        .font(.ourioMicro)
                        .foregroundStyle(glance.isAtRisk ? Ink.accentText : Ink.textSecondary)
                        .lineLimit(1)
                }
                ProgressBar(value: glance.progress).widgetAccentable()
            }
        }
        .padding(Space.m)
        .slab()
        .accessibilityElement(children: .combine)
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
        MochiStage(entry: entry, carries: true)
            .padding(Space.s)
    }

    private var medium: some View {
        HStack(spacing: Space.m) {
            MochiStage(entry: entry, showsSpeech: false)
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Text(pose.word).font(.ourioTitle).foregroundStyle(Ink.text).lineLimit(1).minimumScaleFactor(0.7)
                    if !calm { LevelChip(level: entry.facts.wallet.level) }
                }
                SpeechBubble(text: pose.speech(s, drawing: entry.facts.drawing), font: .ourioCaption, lines: 1)
                Spacer(minLength: Space.xs)
                HStack(spacing: Space.s) {
                    CareButton(care: pose.care, catName: s.catName)
                    if !calm { HugButton(sent: HugState.sent(s), partner: s.partner) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.m)
    }

    private var large: some View {
        VStack(spacing: Space.m) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(pose.word).font(.ourioLargeTitle).foregroundStyle(Ink.text).lineLimit(1).minimumScaleFactor(0.7)
                    Text(line).font(.ourioCaption).foregroundStyle(Ink.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                LevelChip(level: entry.facts.wallet.level)
            }
            MochiStage(entry: entry, speechFont: .ourioCaption)
            StreakTile(glance: streak)
            HStack(spacing: Space.s) {
                CareButton(care: pose.care, catName: s.catName)
                HugButton(sent: HugState.sent(s), partner: s.partner)
                Spacer(minLength: 0)
            }
        }
        .padding(Space.l)
    }
}

private extension PartnerNews {
    var mood: PartnerMood? {
        if case .mood(let check) = self { check.mood } else { nil }
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
            .padding(Space.m)
        case .systemLarge:
            VStack(spacing: Space.m) {
                days.frame(maxHeight: .infinity)
                nextTile.frame(height: 112)
                StreakTile(glance: streak)
            }
            .padding(Space.l)
        default:
            days.padding(Space.m)
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

    @ViewBuilder
    private var nextTile: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let next = s.next {
                RowIcon(symbol: next.icon.symbol, tint: .honey, size: Size.tileMark, style: .clay).widgetAccentable()
                Spacer(minLength: 0)
                Text(next.title).font(.ourioHeadline).foregroundStyle(Ink.text).lineLimit(2)
                Text(next.daysLeft == 0 ? "Today" : "in \(next.daysLeft) \(next.daysLeft == 1 ? "day" : "days")")
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textSecondary)
                ProgressBar(value: Double(Self.countdownDays - min(next.daysLeft, Self.countdownDays)),
                            total: Double(Self.countdownDays))
                    .widgetAccentable()
            } else {
                Spacer(minLength: 0)
                Text("Add a date in Us").font(.ourioHeadline).foregroundStyle(Ink.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(Space.m)
        .slab()
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
                card.frame(width: 130)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(headline).font(.ourioTitle).foregroundStyle(Ink.text).lineLimit(2).minimumScaleFactor(0.7)
                    if let news {
                        Text(news.sentLabel(relativeTo: s.date)).font(.ourioCaption).foregroundStyle(Ink.textSecondary)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: Space.s) {
                        HugButton(sent: HugState.sent(s), partner: s.partner)
                        ReplyLine()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .privacySensitive()
            }
            .padding(Space.l)
        } else {
            VStack(spacing: Space.s) {
                card.frame(maxHeight: .infinity)
                Text("From \(s.partner)").font(.ourioHeadline).foregroundStyle(Ink.text).lineLimit(1)
                if news != nil { ReplyLine() }
            }
            .padding(Space.m)
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
        .rotationEffect(.degrees(-2))
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
            .padding(Space.l)
        } else {
            balance.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(Space.m)
        }
    }

    private var balance: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            CoinIcon(size: 36).widgetAccentable()
            Spacer(minLength: 0)
            Text(glance.coins.formatted())
                .font(.ourioNumber)
                .monospacedDigit()
                .foregroundStyle(Ink.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(glance.caption).font(.ourioCaption).foregroundStyle(Ink.textSecondary).lineLimit(2).minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(glance.coins) coins")
    }

    private var levelTile: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Care level").font(.ourioMicro).foregroundStyle(Ink.textSecondary)
            Text("Lv \(glance.level)").font(.ourioTitle).monospacedDigit().foregroundStyle(Ink.accentText).widgetAccentable()
            ProgressBar(value: glance.progress).widgetAccentable()
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
            .padding(Space.l)
        case .systemLarge:
            print.padding(Space.l)
        default:
            print.padding(Space.m)
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
                .frame(height: 170)
            HStack(spacing: 0) {
                Link(destination: DeepLink.calendar.url) { UsFamilyView(entry: entry, family: .systemSmall, calm: true) }
                Link(destination: DeepLink.inbox.url) { PartnerFamilyView(entry: entry, family: .systemSmall) }
            }
            .frame(maxHeight: .infinity)
        }
    }
}
