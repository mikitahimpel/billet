import Design
import DrawInterface
import MoodInterface
import OurioShared
import SwiftUI
import UIKit
import WidgetKit

// The Home Screen family: one idea per widget, each a clay object on warm paper. Honey is spent once per widget.

// MARK: - Widgets

struct MochiFamilyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ourio.app.cat", provider: FamilyProvider()) { entry in
            FamilyBody { MochiFamilyView(entry: entry, family: $0) }.familyGround()
        }
        .configurationDisplayName("Mochi")
        .description("Your cat, how she is right now, and a pet button.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct UsFamilyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ourio.app.us", provider: FamilyProvider()) { entry in
            FamilyBody { UsFamilyView(entry: entry, family: $0) }.familyGround().widgetURL(DeepLink.calendar.url)
        }
        .configurationDisplayName("Days together")
        .description("Your days together, the next date and the streak.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct PartnerFamilyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ourio.app.partner", provider: FamilyProvider()) { entry in
            FamilyBody { PartnerFamilyView(entry: entry, family: $0) }.familyGround().widgetURL(DeepLink.inbox.url)
        }
        .configurationDisplayName("From your partner")
        .description("Their latest drawing or mood, with a tap to reply.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct CoinsFamilyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ourio.app.coins", provider: FamilyProvider()) { entry in
            FamilyBody { CoinsFamilyView(entry: entry, family: $0) }.familyGround().widgetURL(DeepLink.room.url)
        }
        .configurationDisplayName("Coins")
        .description("Your coins and how far Mochi's care has come.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct MemoryFamilyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ourio.app.memory", provider: FamilyProvider(loadsPhoto: true)) { entry in
            FamilyBody { MemoryFamilyView(entry: entry, family: $0) }.familyGround().widgetURL(DeepLink.moments.url)
        }
        .configurationDisplayName("Memory")
        .description("A pinned moment, printed like a photo.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

/// Large: Mochi over the two things that matter most, days together and the partner.
struct DayFamilyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ourio.app.day", provider: FamilyProvider()) { entry in
            FamilyBody { DayFamilyView(entry: entry, family: $0) }.familyGround()
        }
        .configurationDisplayName("Our day")
        .description("Mochi, your days together and your partner, in one.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

/// Hands the widget's family to a view that takes it as a parameter, so a bigger widget can lay a smaller one out.
struct FamilyBody<Content: View>: View {
    let content: (WidgetFamily) -> Content
    @Environment(\.widgetFamily) private var family

    init(@ViewBuilder content: @escaping (WidgetFamily) -> Content) { self.content = content }

    var body: some View { content(family) }
}

// MARK: - Ground

extension View {
    /// Warm paper under the widget; tinted and clear Home Screens draw the system's own ground instead.
    func familyGround() -> some View {
        modifier(FamilyGround()).widgetTypeCap()
    }
}

private struct FamilyGround: ViewModifier {
    @Environment(\.widgetRenderingMode) private var mode

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            if mode == .fullColor {
                LinearGradient(colors: [Ink.screen, Ink.surfaceRaised], startPoint: .top, endPoint: .bottom)
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - Pieces

private struct LevelChip: View {
    let level: Int

    var body: some View {
        Text("Lv \(level)")
            .font(.ourioMicro)
            .monospacedDigit()
            .foregroundStyle(Ink.heroInk)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(Color.honey, in: .capsule)
            .widgetAccentable()
            .accessibilityLabel("Level \(level)")
    }
}

/// The one honey control of a widget that has one.
private struct PetPill: View {
    let catName: String

    var body: some View {
        Button(intent: PetMochiIntent()) {
            Label("Pet", systemImage: "pawprint.fill")
                .font(.ourioCaption.weight(.bold))
                .foregroundStyle(Ink.heroInk)
                .padding(.horizontal, Space.m)
                .frame(height: Size.pill)
                .background(Color.honey, in: .capsule)
        }
        .buttonStyle(PressScaleStyle())
        .widgetAccentable()
        .accessibilityLabel("Pet \(catName)")
    }
}

private struct ReplyPill: View {
    var body: some View {
        Text("Tap to reply")
            .font(.ourioMicro)
            .foregroundStyle(Ink.heroInk)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(Color.honey, in: .capsule)
            .widgetAccentable()
    }
}

/// Mochi on her disc, the room's colour at night; her state shows as a mark on the disc, not as a different cat.
private struct MochiPortrait: View {
    let snapshot: OurioSnapshot
    let pose: MochiPose
    let size: CGFloat
    var partnerMood: PartnerMood?
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        ZStack {
            if mode == .fullColor {
                Circle().fill(pose == .asleep ? WidgetScene.room(night: true)[0] : Ink.surfaceRaised)
            }
            portrait
                .frame(width: size * 0.9, height: size * 0.9)
                .scaleEffect(pose == .purring ? 1.04 : 1)
            mark.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(snapshot.catName), \(pose.word.lowercased())")
    }

    @ViewBuilder
    private var portrait: some View {
        if let image = UIImage(named: snapshot.catAvatar) ?? UIImage(named: "MochiPortrait") {
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
        case .purring:
            Image(systemName: "heart.fill")
                .font(.ourioHeadline)
                .foregroundStyle(Color.blushPink)
                .widgetAccentable()
        case .asleep:
            Image(systemName: "moon.zzz.fill")
                .font(.ourioHeadline)
                .foregroundStyle(Color.honey)
                .widgetAccentable()
        case .waiting:
            if let partnerMood {
                MoodArt(mood: partnerMood, size: size * 0.24)
            } else {
                Image(systemName: "envelope.fill")
                    .font(.ourioHeadline)
                    .foregroundStyle(Color.honey)
                    .widgetAccentable()
            }
        case .chirpy:
            Image(systemName: "music.note")
                .font(.ourioHeadline)
                .foregroundStyle(Color.honey)
                .widgetAccentable()
        case .napping, .quiet, .idle:
            EmptyView()
        }
    }
}

// MARK: - Mochi

struct MochiFamilyView: View {
    let entry: FamilyEntry
    let family: WidgetFamily

    private var s: OurioSnapshot { entry.snapshot }
    private var pose: MochiPose { MochiPose.pose(s, drawing: entry.facts.drawing) }
    private var line: String { pose.line(s, drawing: entry.facts.drawing) }
    private var mood: PartnerMood? { PartnerNews.latest(s, drawing: entry.facts.drawing).flatMap(\.mood) }

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
        ZStack(alignment: .bottomTrailing) {
            MochiPortrait(snapshot: s, pose: pose, size: 128, partnerMood: mood)
                .offset(x: Space.s, y: Space.s)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(pose.word).font(.ourioHeadline).foregroundStyle(Ink.text).lineLimit(2)
                Text(line).font(.ourioMicro).foregroundStyle(Ink.textSecondary).lineLimit(2)
                Spacer(minLength: 0)
                LevelChip(level: entry.facts.wallet.level)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Space.m)
        }
    }

    private var medium: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(pose.word).font(.ourioTitle).foregroundStyle(Ink.text).lineLimit(1).minimumScaleFactor(0.7)
                Text(line).font(.ourioCaption).foregroundStyle(Ink.textSecondary).lineLimit(2)
                Spacer(minLength: 0)
                HStack(spacing: Space.s) {
                    PetPill(catName: s.catName)
                    LevelChip(level: entry.facts.wallet.level)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MochiPortrait(snapshot: s, pose: pose, size: 146, partnerMood: mood)
        }
        .padding(Space.l)
    }

    private var large: some View {
        VStack(spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(pose.word).font(.ourioLargeTitle).foregroundStyle(Ink.text).lineLimit(1).minimumScaleFactor(0.7)
                    Text(line).font(.ourioCaption).foregroundStyle(Ink.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                LevelChip(level: entry.facts.wallet.level)
            }
            Spacer(minLength: 0)
            MochiPortrait(snapshot: s, pose: pose, size: 232, partnerMood: mood)
            Spacer(minLength: 0)
            PetPill(catName: s.catName)
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

    private var s: OurioSnapshot { entry.snapshot }
    private var streak: StreakGlance { StreakGlance(entry.facts.streak, on: s.date) }

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: Space.m) {
                days.frame(maxWidth: .infinity)
                nextTile
            }
            .padding(Space.l)
        case .systemLarge:
            VStack(spacing: Space.m) {
                days.frame(maxHeight: .infinity)
                nextTile.frame(height: 96)
                StreakRow(glance: streak)
            }
            .padding(Space.l)
        default:
            days.padding(Space.m)
        }
    }

    private var days: some View {
        VStack(spacing: 0) {
            Image(systemName: "heart.fill").font(.ourioHeadline).foregroundStyle(Color.blushPink).widgetAccentable()
            Text("\(s.daysTogether)")
                .font(.ourioNumber)
                .monospacedDigit()
                .foregroundStyle(Ink.accentText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
            Text(s.daysTogether == 1 ? "day together" : "days together")
                .font(.ourioCaption)
                .foregroundStyle(Ink.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var nextTile: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let next = s.next {
                Image(systemName: next.icon.symbol).font(.ourioHeadline).foregroundStyle(Ink.accentText).widgetAccentable()
                Spacer(minLength: 0)
                Text(next.title).font(.ourioHeadline).foregroundStyle(Ink.text).lineLimit(2)
                Text(next.daysLeft == 0 ? "Today" : "in \(next.daysLeft) \(next.daysLeft == 1 ? "day" : "days")")
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textSecondary)
            } else {
                Spacer(minLength: 0)
                Text("Add a date in Us").font(.ourioHeadline).foregroundStyle(Ink.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(Space.m)
        .background(Ink.surface, in: ContainerRelativeShape())
    }
}

private struct StreakRow: View {
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
                    Text(glance.caption).font(.ourioMicro).foregroundStyle(Ink.textSecondary).lineLimit(1)
                }
                Bar(value: glance.progress)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct Bar: View {
    let value: Double

    var body: some View {
        Capsule()
            .fill(Ink.separator)
            .frame(height: Space.s + Space.xs)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule().fill(Color.honey).frame(width: max(Space.s + Space.xs, geo.size.width * value))
                }
            }
            .widgetAccentable()
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
                        Text("\(Text(news.date, style: .relative)) ago").font(.ourioCaption).foregroundStyle(Ink.textSecondary)
                    }
                    Spacer(minLength: 0)
                    ReplyPill()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .privacySensitive()
            }
            .padding(Space.l)
        } else {
            VStack(spacing: Space.s) {
                card.frame(maxHeight: .infinity)
                Text(s.partner).font(.ourioHeadline).foregroundStyle(Ink.text).lineLimit(1)
                if news != nil { ReplyPill() }
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
            content.padding(Space.s)
            PostageStamp(.heart, size: .regular)
                .rotationEffect(.degrees(6))
                .offset(x: Space.xs, y: -Space.xs)
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
            Text(glance.caption).font(.ourioCaption).foregroundStyle(Ink.textSecondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(glance.coins) coins")
    }

    private var levelTile: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Care level").font(.ourioMicro).foregroundStyle(Ink.textSecondary)
            Text("Lv \(glance.level)").font(.ourioTitle).monospacedDigit().foregroundStyle(Ink.accentText).widgetAccentable()
            Bar(value: glance.progress)
            Text("\(Int((glance.progress * 100).rounded()))% to Lv \(glance.level + 1)")
                .font(.ourioMicro)
                .foregroundStyle(Ink.textSecondary)
        }
        .frame(width: 140, alignment: .leading)
        .padding(Space.m)
        .frame(maxHeight: .infinity)
        .background(Ink.surface, in: ContainerRelativeShape())
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
                    Text(caption.isEmpty ? "Together" : caption).font(.ourioHeadline).foregroundStyle(Ink.text).lineLimit(3)
                    if let date = entry.momentDate {
                        Text(date, format: .dateTime.day().month(.wide).year())
                            .font(.ourioCaption).foregroundStyle(Ink.textSecondary)
                    }
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
                        Ink.surfaceRaised.overlay {
                            Image(systemName: "photo.on.rectangle.angled").font(.ourioTitle).foregroundStyle(Ink.textTertiary)
                        }
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
            PostageStamp(.paw, size: .regular).rotationEffect(.degrees(8)).offset(x: Space.s, y: -Space.s)
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
            MochiFamilyView(entry: entry, family: .systemMedium)
                .frame(height: 170)
            HStack(spacing: 0) {
                Link(destination: DeepLink.calendar.url) { UsFamilyView(entry: entry, family: .systemSmall) }
                Link(destination: DeepLink.inbox.url) { PartnerFamilyView(entry: entry, family: .systemSmall) }
            }
            .frame(maxHeight: .infinity)
        }
    }
}
