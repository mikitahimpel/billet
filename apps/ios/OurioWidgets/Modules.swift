import AppIntents
import MomentsInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import Design
import UIKit
import UsInterface
import WidgetKit

/// One module, padded and linked to its screen in the app.
struct ModuleView: View {
    let module: WidgetModule
    let snapshot: OurioSnapshot
    var smart = false
    var momentImage: Data?

    var body: some View {
        Group {
            switch module {
            case .mochi: MochiRoom(snapshot: snapshot)
            case .us: UsModule(snapshot: snapshot, smart: smart).padding(Space.m)
            case .mood: MoodModule(snapshot: snapshot, smart: smart).padding(Space.m)
            case .list: ListModule(snapshot: snapshot, smart: smart).padding(Space.m)
            case .date: DateModule(snapshot: snapshot, smart: smart).padding(Space.m)
            case .moment: MomentModule(snapshot: snapshot, image: momentImage)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetTypeCap()
    }

    var link: DeepLink { module.link(in: snapshot) }
}

extension WidgetModule {
    func link(in snapshot: OurioSnapshot) -> DeepLink {
        switch self {
        case .mochi, .mood: .room
        case .us: .calendar
        case .list: snapshot.list.map { .list($0.id) } ?? .us
        case .date: .dates
        case .moment: .moments
        }
    }
}

private struct ModuleHeader: View {
    let title: String
    var smart = false

    var body: some View {
        HStack(spacing: Space.xs) {
            Text(title.uppercased())
                .font(.ourioMicro)
                .tracking(0.4)
                .foregroundStyle(Ink.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if smart {
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Ink.accentText)
                    .widgetAccentable()
            }
        }
    }
}

private struct BigNumber: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.ourioLargeTitle)
            .foregroundStyle(Ink.accentText)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .contentTransition(.numericText())
            .widgetAccentable()
    }
}

// MARK: - Mochi

/// Mochi in a drawn corner of the room, with a pet button.
/// note: the app's hero figure, not a render of the real diorama; a RealityKit snapshot can replace it once bought
/// items actually appear in the room.
struct MochiRoom: View {
    let snapshot: OurioSnapshot
    var showsCaption = true
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                // Tinted and clear Home Screens draw everything in one tint, where the room's fills would turn into
                // flat grey blocks: there Mochi sits on the system's own background.
                if renderingMode == .fullColor { room(in: size) }
                // She sits on the floor at the room's right, her paws on the rug.
                mochi
                    .frame(height: size.height * 0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, size.width * 0.05)
                    .padding(.bottom, size.height * 0.04)
                if snapshot.isPurring { hearts(in: size) }
                if showsCaption { caption.padding(10) }
                PetButton(catName: snapshot.catName)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(10)
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func room(in size: CGSize) -> some View {
        LinearGradient(colors: WidgetScene.room(night: snapshot.isNight), startPoint: .top, endPoint: .bottom)
        WidgetScene.floor(night: snapshot.isNight)
            .frame(height: size.height * 0.3)
            .frame(maxHeight: .infinity, alignment: .bottom)
        window
            .frame(width: size.width * 0.24, height: size.height * 0.3)
            .offset(x: size.width * 0.08, y: size.height * 0.16)
        Ellipse()
            .fill(Color(hex: snapshot.isNight ? 0x8A5A57 : 0xE8A497))
            .frame(width: size.width * 0.62, height: size.height * 0.14)
            .offset(x: size.width * 0.28, y: size.height * 0.8)
    }

    private var window: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(LinearGradient(colors: snapshot.isNight ? [Color(hex: 0x1D2A4A), Color(hex: 0x3C4C78)]
                                                          : [Color(hex: 0xBFE0F2), Color(hex: 0xE8F4FA)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.white.opacity(0.9), lineWidth: 3))
    }

    private var mochi: some View {
        CatFigure(avatar: snapshot.catAvatar, asleep: snapshot.isNight)
            .scaleEffect(snapshot.isPurring ? 1.05 : 1, anchor: .bottom)
    }

    private func hearts(in size: CGSize) -> some View {
        ForEach(0..<3, id: \.self) { i in
            Image(systemName: "heart.fill")
                .font(.system(size: [16, 12, 13][i]))
                .foregroundStyle(Color.blushPink)
                .widgetAccentable()
                // Around her head, which stands at the room's right.
                .offset(x: size.width * 0.95 - size.height * [0.46, 0.26, 0.56][i],
                        y: size.height * [0.1, 0.04, 0.22][i])
        }
    }

    private var caption: some View {
        Text("\(snapshot.catName) · \(pose)")
            .font(.ourioMicro)
            .foregroundStyle(Ink.heroInk)
            .lineLimit(1)
            .padding(.horizontal, Space.s)
            .padding(.vertical, 3)
            .background(.white.opacity(0.88), in: .capsule)
    }

    /// Mochi takes after the partner's check-in; never sad, whatever the couple does or doesn't do.
    private var pose: String {
        if snapshot.isPurring { return "purring" }
        if snapshot.isNight { return "asleep" }
        switch snapshot.freshPartnerMood?.mood {
        case .sleepy: return "napping"
        case .missing: return "waiting by the window"
        case .happy: return "chirpy"
        case .busy: return "keeping quiet"
        case nil: return "sitting pretty"
        }
    }
}

private struct PetButton: View {
    let catName: String

    var body: some View {
        Button(intent: PetMochiIntent()) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 15, weight: .semibold))
                // On a white chip in either appearance, so the fixed deep honey rather than the adaptive accent.
                .foregroundStyle(Color.honeyDeep)
                .widgetAccentable()
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.92), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pet \(catName)")
    }
}

// MARK: - Together

struct UsModule: View {
    let snapshot: OurioSnapshot
    var smart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ModuleHeader(title: "Together", smart: smart)
            Spacer(minLength: 0)
            if let next = snapshot.next, next.daysLeft <= 3 {
                BigNumber(text: next.daysLeft == 0 ? "Today" : "\(next.daysLeft)")
                Text(next.daysLeft == 0 ? next.title : "\(next.daysLeft == 1 ? "day" : "days") to \(next.title)")
                    .font(.ourioCaption.weight(.semibold))
                    .foregroundStyle(Ink.text)
                    .lineLimit(2)
            } else {
                BigNumber(text: "\(snapshot.daysTogether)")
                Text("days together")
                    .font(.ourioCaption.weight(.semibold))
                    .foregroundStyle(Ink.text)
                if let next = snapshot.next {
                    Text("\(next.title) in \(next.daysLeft)d")
                        .font(.ourioMicro)
                        .foregroundStyle(Ink.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Mood

struct MoodModule: View {
    let snapshot: OurioSnapshot
    var smart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModuleHeader(title: "Mood", smart: smart)
            if let check = snapshot.partnerMood {
                HStack(spacing: 5) {
                    MoodArt(mood: check.mood, size: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(snapshot.partner) · \(check.mood.title)")
                            .font(.ourioCaption.weight(.semibold))
                            .foregroundStyle(Ink.text)
                            .privacySensitive()
                        Text("\(Text(check.date, style: .relative)) ago")
                            .font(.ourioMicro)
                            .foregroundStyle(Ink.textSecondary)
                    }
                    .lineLimit(1)
                }
            } else {
                Text("How are you, \(snapshot.viewer)?")
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(spacing: 5) {
                HStack(spacing: 5) { moodButton(.happy); moodButton(.sleepy) }
                HStack(spacing: 5) { moodButton(.missing); moodButton(.busy) }
            }
        }
    }

    /// Lit when it is the viewer's check-in from today.
    private func isMine(_ mood: PartnerMood) -> Bool {
        guard let mine = snapshot.myMood else { return false }
        return mine.mood == mood && Calendar.current.isDate(mine.date, inSameDayAs: snapshot.date)
    }

    private func moodButton(_ mood: PartnerMood) -> some View {
        Button(intent: SetMoodIntent(mood)) {
            MoodArt(mood: mood, size: 20)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(isMine(mood) ? Color.honey : Ink.surfaceRaised,
                            in: .rect(cornerRadius: Radius.inner, style: .continuous))
                .widgetAccentable(isMine(mood))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mood.title)
    }
}

// MARK: - List

struct ListModule: View {
    let snapshot: OurioSnapshot
    var smart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModuleHeader(title: snapshot.list?.title ?? "Lists", smart: smart)
            if let list = snapshot.list, !list.items.isEmpty {
                ForEach(list.items, id: \.id) { item in
                    Button(intent: SetListItemIntent(listID: list.id, itemID: item.id, done: !item.done)) {
                        row(item)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                let hidden = list.openCount - list.items.filter { !$0.done }.count
                if hidden > 0 {
                    Text("+\(hidden) more")
                        .font(.ourioMicro)
                        .foregroundStyle(Ink.textSecondary)
                }
            } else {
                Spacer(minLength: 0)
                Text("Nothing on the list")
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textSecondary)
                Spacer(minLength: 0)
            }
        }
    }

    private func row(_ item: OurioSnapshot.ListPreview.Item) -> some View {
        HStack(spacing: 7) {
            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Ink.accentText)
                .widgetAccentable()
            Text(item.text)
                .font(.ourioCaption)
                .strikethrough(item.done)
                .foregroundStyle(item.done ? Ink.textSecondary : Ink.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(item.author)
                .font(.ourioMicro)
                .foregroundStyle(Ink.textSecondary)
        }
        .contentShape(.rect)
    }
}

// MARK: - Date

struct DateModule: View {
    let snapshot: OurioSnapshot
    var smart = false

    /// A planned date takes the module from a week before; until then it deals ideas.
    private var plan: OurioSnapshot.PlannedPreview? {
        snapshot.planned.flatMap { $0.date.timeIntervalSince(snapshot.date) < 7 * 86_400 ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let plan {
                ModuleHeader(title: plan.isToday ? "Date night" : "Next date", smart: smart)
                Spacer(minLength: 0)
                Text(plan.title)
                    .font(.ourioCallout.weight(.bold))
                    .foregroundStyle(Ink.text)
                    .lineLimit(2)
                Text(plan.date, format: plan.isToday ? Date.FormatStyle.dateTime.hour().minute()
                                                     : Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(plan.isToday ? .ourioTitle : .ourioCallout.weight(.bold))
                    .foregroundStyle(Ink.accentText)
                    .widgetAccentable()
                if let hint = plan.hint {
                    Text("Hint: \(hint)")
                        .font(.ourioMicro)
                        .foregroundStyle(Ink.textSecondary)
                        .lineLimit(2)
                }
            } else {
                ModuleHeader(title: "Date idea", smart: smart)
                if let idea = snapshot.idea {
                    Text(idea.title)
                        .font(.ourioCallout.weight(.bold))
                        .foregroundStyle(Ink.text)
                        .lineLimit(2)
                        .padding(.top, 2)
                    Text(idea.matched ? "You both liked it" : idea.pitch)
                        .font(.ourioMicro)
                        .foregroundStyle(Ink.textSecondary)
                        .lineLimit(2)
                } else {
                    Text("Can't decide what to do tonight?")
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.textSecondary)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                Button(intent: SurpriseIdeaIntent()) {
                    Label(snapshot.idea == nil ? "Surprise us" : "Another", systemImage: "dice.fill")
                        .font(.ourioCaption.weight(.bold))
                        .foregroundStyle(Ink.heroInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.honey, in: .capsule)
                }
                .buttonStyle(.plain)
                .widgetAccentable()
            }
        }
    }
}

// MARK: - Moment

struct MomentModule: View {
    let snapshot: OurioSnapshot
    let image: Data?

    var body: some View {
        if let image, let photo = UIImage(data: image) {
            ZStack(alignment: .bottomLeading) {
                Color.clear.overlay {
                    Image(uiImage: photo)
                        .resizable()
                        .widgetAccentedRenderingMode(.fullColor)
                        .scaledToFill()
                        .privacySensitive()
                }
                .clipped()
                if let caption = snapshot.moment?.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.ourioMicro)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, Space.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ModuleHeader(title: "Moment")
                Spacer(minLength: 0)
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 22))
                    .foregroundStyle(Ink.accentText)
                    .widgetAccentable()
                Text("Pin a photo to the garland")
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
            .padding(Space.m)
        }
    }
}
