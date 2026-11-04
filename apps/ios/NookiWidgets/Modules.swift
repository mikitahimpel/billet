import AppIntents
import SwiftUI
import UIKit
import WidgetKit

/// One module, padded and linked to its screen in the app.
struct ModuleView: View {
    let module: WidgetModule
    let snapshot: NookiSnapshot
    var smart = false
    var momentImage: Data?

    var body: some View {
        Group {
            switch module {
            case .mochi: MochiRoom(snapshot: snapshot)
            case .us: UsModule(snapshot: snapshot, smart: smart).padding(12)
            case .mood: MoodModule(snapshot: snapshot, smart: smart).padding(12)
            case .list: ListModule(snapshot: snapshot, smart: smart).padding(12)
            case .date: DateModule(snapshot: snapshot, smart: smart).padding(12)
            case .moment: MomentModule(snapshot: snapshot, image: momentImage)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var link: DeepLink { module.link(in: snapshot) }
}

extension WidgetModule {
    func link(in snapshot: NookiSnapshot) -> DeepLink {
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
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(.widget(10, .bold))
                .tracking(0.4)
                .foregroundStyle(WidgetInk.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if smart {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WidgetInk.accent)
                    .widgetAccentable()
            }
        }
    }
}

private struct BigNumber: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.widget(32, .bold))
            .foregroundStyle(WidgetInk.accent)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .contentTransition(.numericText())
            .widgetAccentable()
    }
}

// MARK: - Mochi

/// Mochi in a drawn corner of the room, with a pet button.
/// note: the portrait, not a render of the real diorama; a RealityKit snapshot can replace it once bought items
/// actually appear in the room.
struct MochiRoom: View {
    let snapshot: NookiSnapshot
    var showsCaption = true

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: WidgetInk.room(night: snapshot.isNight), startPoint: .top, endPoint: .bottom)
                WidgetInk.floor(night: snapshot.isNight)
                    .frame(height: size.height * 0.3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                window
                    .frame(width: size.width * 0.24, height: size.height * 0.3)
                    .offset(x: size.width * 0.08, y: size.height * 0.16)
                Ellipse()
                    .fill(Color(hex: snapshot.isNight ? 0x8A5A57 : 0xE8A497))
                    .frame(width: size.width * 0.62, height: size.height * 0.14)
                    .offset(x: size.width * 0.28, y: size.height * 0.8)
                mochi
                    .frame(width: size.height * 0.78, height: size.height * 0.78)
                    .offset(x: size.width - size.height * 0.66, y: size.height * 0.3)
                if snapshot.isPurring { hearts(in: size) }
                if showsCaption { caption.padding(10) }
                PetButton()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(10)
            }
        }
        .clipped()
    }

    private var window: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(LinearGradient(colors: snapshot.isNight ? [Color(hex: 0x1D2A4A), Color(hex: 0x3C4C78)]
                                                          : [Color(hex: 0xBFE0F2), Color(hex: 0xE8F4FA)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.white.opacity(0.9), lineWidth: 3))
    }

    @ViewBuilder
    private var mochi: some View {
        if let portrait = UIImage(named: "MochiPortrait") {
            Image(uiImage: portrait)
                .resizable()
                .widgetAccentedRenderingMode(.desaturated)
                .scaledToFit()
                .scaleEffect(snapshot.isPurring ? 1.05 : 1)
        } else {
            Image(systemName: "cat.fill").resizable().scaledToFit().foregroundStyle(.white)
        }
    }

    private func hearts(in size: CGSize) -> some View {
        ForEach(0..<3, id: \.self) { i in
            Image(systemName: "heart.fill")
                .font(.system(size: [16, 11, 13][i]))
                .foregroundStyle(Color.blushPink)
                .widgetAccentable()
                .offset(x: size.width * [0.5, 0.62, 0.44][i], y: size.height * [0.12, 0.06, 0.24][i])
        }
    }

    private var caption: some View {
        Text("Mochi · \(pose)")
            .font(.widget(11, .semibold))
            .foregroundStyle(Color(hex: 0x2B2420))
            .lineLimit(1)
            .padding(.horizontal, 8)
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
    var body: some View {
        Button(intent: PetMochiIntent()) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WidgetInk.accent)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.92), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pet Mochi")
    }
}

// MARK: - Together

struct UsModule: View {
    let snapshot: NookiSnapshot
    var smart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ModuleHeader(title: "Together", smart: smart)
            Spacer(minLength: 0)
            if let next = snapshot.next, next.daysLeft <= 3 {
                BigNumber(text: next.daysLeft == 0 ? "Today" : "\(next.daysLeft)")
                Text(next.daysLeft == 0 ? next.title : "\(next.daysLeft == 1 ? "day" : "days") to \(next.title)")
                    .font(.widget(13, .semibold))
                    .foregroundStyle(WidgetInk.primary)
                    .lineLimit(2)
            } else {
                BigNumber(text: "\(snapshot.daysTogether)")
                Text("days together")
                    .font(.widget(13, .semibold))
                    .foregroundStyle(WidgetInk.primary)
                if let next = snapshot.next {
                    Text("\(next.title) in \(next.daysLeft)d")
                        .font(.widget(11))
                        .foregroundStyle(WidgetInk.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Mood

struct MoodModule: View {
    let snapshot: NookiSnapshot
    var smart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModuleHeader(title: "Mood", smart: smart)
            if let check = snapshot.partnerMood {
                HStack(spacing: 5) {
                    Text(check.mood.emoji).font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(snapshot.partner) · \(check.mood.title)")
                            .font(.widget(12, .semibold))
                            .foregroundStyle(WidgetInk.primary)
                            .privacySensitive()
                        Text("\(Text(check.date, style: .relative)) ago")
                            .font(.widget(10))
                            .foregroundStyle(WidgetInk.secondary)
                    }
                    .lineLimit(1)
                }
            } else {
                Text("How are you, \(snapshot.viewer)?")
                    .font(.widget(12, .medium))
                    .foregroundStyle(WidgetInk.secondary)
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
            Text(mood.emoji)
                .font(.system(size: 15))
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(isMine(mood) ? WidgetInk.accent.opacity(0.9) : WidgetInk.card,
                            in: .rect(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mood.title)
    }
}

// MARK: - List

struct ListModule: View {
    let snapshot: NookiSnapshot
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
                        .font(.widget(10, .medium))
                        .foregroundStyle(WidgetInk.secondary)
                }
            } else {
                Spacer(minLength: 0)
                Text("Nothing on the list")
                    .font(.widget(12, .medium))
                    .foregroundStyle(WidgetInk.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    private func row(_ item: NookiSnapshot.ListPreview.Item) -> some View {
        HStack(spacing: 7) {
            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WidgetInk.accent)
                .widgetAccentable()
            Text(item.text)
                .font(.widget(13, .medium))
                .strikethrough(item.done)
                .foregroundStyle(item.done ? WidgetInk.secondary : WidgetInk.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(item.author)
                .font(.widget(9, .bold))
                .foregroundStyle(WidgetInk.secondary)
        }
        .contentShape(.rect)
    }
}

// MARK: - Date

struct DateModule: View {
    let snapshot: NookiSnapshot
    var smart = false

    /// A planned date takes the module from a week before; until then it deals ideas.
    private var plan: NookiSnapshot.PlannedPreview? {
        snapshot.planned.flatMap { $0.date.timeIntervalSince(snapshot.date) < 7 * 86_400 ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let plan {
                ModuleHeader(title: plan.isToday ? "Date night" : "Next date", smart: smart)
                Spacer(minLength: 0)
                Text(plan.title)
                    .font(.widget(14, .bold))
                    .foregroundStyle(WidgetInk.primary)
                    .lineLimit(2)
                Text(plan.date, format: plan.isToday ? Date.FormatStyle.dateTime.hour().minute()
                                                     : Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.widget(plan.isToday ? 22 : 14, .bold))
                    .foregroundStyle(WidgetInk.accent)
                    .widgetAccentable()
                if let hint = plan.hint {
                    Text("Hint: \(hint)")
                        .font(.widget(11))
                        .foregroundStyle(WidgetInk.secondary)
                        .lineLimit(2)
                }
            } else {
                ModuleHeader(title: "Date idea", smart: smart)
                if let idea = snapshot.idea {
                    Text(idea.title)
                        .font(.widget(14, .bold))
                        .foregroundStyle(WidgetInk.primary)
                        .lineLimit(2)
                        .padding(.top, 2)
                    Text(idea.matched ? "You both liked it" : idea.pitch)
                        .font(.widget(11))
                        .foregroundStyle(WidgetInk.secondary)
                        .lineLimit(2)
                } else {
                    Text("Can't decide what to do tonight?")
                        .font(.widget(12, .medium))
                        .foregroundStyle(WidgetInk.secondary)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                Button(intent: SurpriseIdeaIntent()) {
                    Label(snapshot.idea == nil ? "Surprise us" : "Another", systemImage: "dice.fill")
                        .font(.widget(12, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(WidgetInk.accent, in: .capsule)
                }
                .buttonStyle(.plain)
                .widgetAccentable()
            }
        }
    }
}

// MARK: - Moment

struct MomentModule: View {
    let snapshot: NookiSnapshot
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
                        .font(.widget(11, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
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
                    .foregroundStyle(WidgetInk.accent)
                    .widgetAccentable()
                Text("Pin a photo to the garland")
                    .font(.widget(12, .medium))
                    .foregroundStyle(WidgetInk.secondary)
            }
            .padding(12)
        }
    }
}
