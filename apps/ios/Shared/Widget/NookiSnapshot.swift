import Foundation

/// The blocks a widget is built from (docs/widget-concept.md, section 2).
enum WidgetModule: String, Codable, CaseIterable {
    case mochi, us, mood, list, date, moment
}

/// Everything the widgets draw at one moment, read from the shared stores. Plain data, so it can be built for future
/// timeline entries and tested without WidgetKit.
struct NookiSnapshot: Hashable {
    struct NextEvent: Hashable {
        var title: String
        var icon: UsGlyph
        var date: Date
        var daysLeft: Int
    }

    struct ListPreview: Hashable {
        struct Item: Hashable {
            var id: UUID
            var text: String
            var author: String
            var done: Bool
        }

        var id: UUID
        var title: String
        var icon: UsGlyph
        /// Open items first, then the ones ticked off today, so a tick in the widget can be undone.
        var items: [Item]
        var openCount: Int
        /// The partner added something to it today.
        var partnerAddedToday: Bool
    }

    struct PlannedPreview: Hashable {
        var id: UUID
        /// "Surprise date" when the partner organizes it in surprise mode.
        var title: String
        var date: Date
        var hint: String?
        var isToday: Bool
    }

    struct IdeaPreview: Hashable {
        var id: Int
        var title: String
        var pitch: String
        var matched: Bool
    }

    struct MomentPreview: Hashable {
        var id: UUID
        var caption: String
        var imageURL: URL
    }

    var date: Date
    var viewer: String
    var partner: String
    var daysTogether: Int
    var next: NextEvent?
    var partnerMood: MoodCheckIn?
    var myMood: MoodCheckIn?
    var list: ListPreview?
    var planned: PlannedPreview?
    var idea: IdeaPreview?
    var moment: MomentPreview?
    var isPurring: Bool
    var isNight: Bool
    var catName = CatProfile.defaultName
    /// Her portrait in the coat picked in onboarding.
    var catAvatar = "MochiPortrait"

    /// Rows a list shows at most, sized for the smallest widget.
    static let listRows = 3
    /// How long a partner's check-in stays news.
    static let moodNews: TimeInterval = 3 * 3600

    var smartModule: WidgetModule { SmartSlot.pick(for: self) }

    /// The partner's check-in while it is still news.
    var freshPartnerMood: MoodCheckIn? {
        guard let partnerMood, date >= partnerMood.date, date.timeIntervalSince(partnerMood.date) < Self.moodNews else { return nil }
        return partnerMood
    }

    /// Night from 20:00 to 7:00, when the room's lamps are on.
    static func isNight(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour < 7 || hour >= 20
    }
}

extension NookiSnapshot {
    /// - Parameter listID: the list the widget was set up with; falls back to the first checklist, then the first list.
    init(date: Date, couple: Couple, moods: [String: MoodCheckIn], activity: WidgetActivity, us: UsStore,
         listID: UUID?, moment: MomentPreview?) {
        let cal = Calendar.current
        let partner = couple.other
        self.date = date
        viewer = couple.viewer
        self.partner = partner
        daysTogether = couple.daysTogether(on: date)
        partnerMood = moods[partner]
        myMood = moods[couple.viewer]
        self.moment = moment
        isPurring = activity.isPurring(at: date)
        isNight = Self.isNight(date)
        catName = CatProfile.name()
        catAvatar = CatProfile.avatar()

        let today = cal.startOfDay(for: date)
        next = us.upcoming(togetherSince: couple.togetherSince, limit: 1, from: date).first.map {
            NextEvent(title: $0.title, icon: $0.icon, date: $0.date,
                      daysLeft: cal.dateComponents([.day], from: today, to: cal.startOfDay(for: $0.date)).day ?? 0)
        }

        let chosen = listID.flatMap(us.list) ?? us.lists.first { $0.kind.isChecklist } ?? us.lists.first
        list = chosen.map { list in
            let open = list.open
            let doneToday = list.finished.filter { $0.done.map { cal.isDate($0, inSameDayAs: date) } ?? false }
            return ListPreview(
                id: list.id, title: list.title, icon: list.icon,
                items: (open + doneToday).prefix(Self.listRows).map {
                    .init(id: $0.id, text: $0.text, author: $0.author, done: $0.done != nil)
                },
                openCount: open.count,
                partnerAddedToday: list.items.contains { $0.author == partner && cal.isDate($0.added, inSameDayAs: date) }
            )
        }

        planned = us.planned
            .filter { $0.rating == nil && $0.date >= today }
            .min { $0.date < $1.date }
            .map { plan in
                let hidden = plan.surprise && plan.organizer != couple.viewer
                return PlannedPreview(id: plan.id,
                                      title: hidden ? "Surprise date" : DateIdea.idea(plan.ideaID)?.title ?? "Date",
                                      date: plan.date,
                                      hint: plan.hint.isEmpty ? nil : plan.hint,
                                      isToday: cal.isDate(plan.date, inSameDayAs: date))
            }

        idea = activity.ideaID.flatMap(DateIdea.idea).map {
            IdeaPreview(id: $0.id, title: $0.title, pitch: $0.pitch, matched: us.isMatch($0.id))
        }
    }
}

/// Picks what the smart slot shows: the first rule that holds wins (docs/widget-concept.md, section 3).
/// note: gifts, notes and today's question rank above the mood once those features exist; they have no data yet.
enum SmartSlot {
    static func pick(for s: NookiSnapshot) -> WidgetModule {
        if s.planned?.isToday == true { return .date }
        if s.freshPartnerMood != nil { return .mood }
        if let next = s.next, next.daysLeft <= 3 { return .us }
        if let list = s.list, list.partnerAddedToday, list.openCount > 0 { return .list }
        return .us
    }
}

/// When the widgets need a new entry without anything being saved: a purr ends, a check-in stops being news, the
/// room turns to night or day, the day counter rolls over.
enum WidgetTimeline {
    static func entryDates(from now: Date, activity: WidgetActivity, moods: [String: MoodCheckIn],
                           horizon: TimeInterval = 24 * 3600) -> [Date] {
        let cal = Calendar.current
        let end = now.addingTimeInterval(horizon)
        var dates: [Date] = [now]
        if let pet = activity.lastPet { dates.append(pet.addingTimeInterval(WidgetActivity.purrLength)) }
        dates += moods.values.map { $0.date.addingTimeInterval(NookiSnapshot.moodNews) }
        for hour in [0, 7, 20] {
            if let next = cal.nextDate(after: now, matching: DateComponents(hour: hour, minute: 0), matchingPolicy: .nextTime) {
                dates.append(next)
            }
        }
        return Set(dates.filter { $0 >= now && $0 <= end }).sorted()
    }
}
