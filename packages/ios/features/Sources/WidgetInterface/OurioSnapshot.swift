import Foundation
import MoodInterface
import ProfileInterface
import UsInterface

public enum WidgetModule: String, Codable, CaseIterable, Sendable {
  case mochi, us, mood, list, date, moment
}

/// Everything the widgets draw at one moment, read from the shared stores. Plain data, so it can be built for future
/// timeline entries and tested without WidgetKit.
public struct OurioSnapshot: Hashable, Sendable {
  public struct NextEvent: Hashable, Sendable {
    public var title: String
    public var icon: UsGlyph
    public var date: Date
    public var daysLeft: Int

    public init(title: String, icon: UsGlyph, date: Date, daysLeft: Int) {
      self.title = title
      self.icon = icon
      self.date = date
      self.daysLeft = daysLeft
    }
  }

  public struct ListPreview: Hashable, Sendable {
    public struct Item: Hashable, Sendable {
      public var id: UUID
      public var text: String
      public var author: String
      public var done: Bool

      public init(id: UUID, text: String, author: String, done: Bool) {
        self.id = id
        self.text = text
        self.author = author
        self.done = done
      }
    }

    public var id: UUID
    public var title: String
    public var icon: UsGlyph
    /// Open items first, then the ones ticked off today, so a tick in the widget can be undone.
    public var items: [Item]
    public var openCount: Int
    /// The partner added something to it today.
    public var partnerAddedToday: Bool

    public init(
      id: UUID, title: String, icon: UsGlyph, items: [Item], openCount: Int, partnerAddedToday: Bool
    ) {
      self.id = id
      self.title = title
      self.icon = icon
      self.items = items
      self.openCount = openCount
      self.partnerAddedToday = partnerAddedToday
    }
  }

  public struct PlannedPreview: Hashable, Sendable {
    public var id: UUID
    /// "Surprise date" when the partner organizes it in surprise mode.
    public var title: String
    public var date: Date
    public var hint: String?
    public var isToday: Bool

    public init(id: UUID, title: String, date: Date, hint: String? = nil, isToday: Bool) {
      self.id = id
      self.title = title
      self.date = date
      self.hint = hint
      self.isToday = isToday
    }
  }

  public struct IdeaPreview: Hashable, Sendable {
    public var id: Int
    public var title: String
    public var pitch: String
    public var matched: Bool

    public init(id: Int, title: String, pitch: String, matched: Bool) {
      self.id = id
      self.title = title
      self.pitch = pitch
      self.matched = matched
    }
  }

  public struct MomentPreview: Hashable, Sendable {
    public var id: UUID
    public var caption: String
    public var imageURL: URL

    public init(id: UUID, caption: String, imageURL: URL) {
      self.id = id
      self.caption = caption
      self.imageURL = imageURL
    }
  }

  public var date: Date
  public var viewer: String
  public var partner: String
  public var daysTogether: Int
  public var next: NextEvent?
  public var partnerMood: MoodCheckIn?
  public var myMood: MoodCheckIn?
  public var list: ListPreview?
  public var planned: PlannedPreview?
  public var idea: IdeaPreview?
  public var moment: MomentPreview?
  public var isPurring: Bool
  public var isNight: Bool
  public var catName = CatProfile.defaultName
  /// In the coat picked in onboarding.
  public var catAvatar = "MochiPortrait"

  public init(
    date: Date, viewer: String, partner: String, daysTogether: Int, next: NextEvent? = nil,
    partnerMood: MoodCheckIn? = nil, myMood: MoodCheckIn? = nil, list: ListPreview? = nil,
    planned: PlannedPreview? = nil, idea: IdeaPreview? = nil, moment: MomentPreview? = nil,
    isPurring: Bool, isNight: Bool, catName: String = CatProfile.defaultName,
    catAvatar: String = "MochiPortrait"
  ) {
    self.date = date
    self.viewer = viewer
    self.partner = partner
    self.daysTogether = daysTogether
    self.next = next
    self.partnerMood = partnerMood
    self.myMood = myMood
    self.list = list
    self.planned = planned
    self.idea = idea
    self.moment = moment
    self.isPurring = isPurring
    self.isNight = isNight
    self.catName = catName
    self.catAvatar = catAvatar
  }

  /// Rows a list shows at most, sized for the smallest widget.
  public static let listRows = 3
  /// How long a partner's check-in stays news.
  public static let moodNews: TimeInterval = 3 * 3600

  public var smartModule: WidgetModule { SmartSlot.pick(for: self) }

  public var freshPartnerMood: MoodCheckIn? {
    guard let partnerMood, date >= partnerMood.date,
      date.timeIntervalSince(partnerMood.date) < Self.moodNews
    else { return nil }
    return partnerMood
  }

  /// Night from 20:00 to 7:00, when the room's lamps are on.
  public static func isNight(_ date: Date) -> Bool {
    let hour = Calendar.current.component(.hour, from: date)
    return hour < 7 || hour >= 20
  }
}

extension OurioSnapshot {
  /// - Parameter listID: the list the widget was set up with; falls back to the first checklist, then the first list.
  public init(
    date: Date, couple: Couple, moods: [String: MoodCheckIn], activity: WidgetActivity, us: UsStore,
    listID: UUID?, moment: MomentPreview?
  ) {
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
      NextEvent(
        title: $0.title, icon: $0.icon, date: $0.date,
        daysLeft: cal.dateComponents([.day], from: today, to: cal.startOfDay(for: $0.date)).day ?? 0
      )
    }

    let chosen = listID.flatMap(us.list) ?? us.lists.first { $0.kind.isChecklist } ?? us.lists.first
    list = chosen.map { list in
      let open = list.open
      let doneToday = list.finished.filter {
        $0.done.map { cal.isDate($0, inSameDayAs: date) } ?? false
      }
      return ListPreview(
        id: list.id, title: list.title, icon: list.icon,
        items: (open + doneToday).prefix(Self.listRows).map {
          .init(id: $0.id, text: $0.text, author: $0.author, done: $0.done != nil)
        },
        openCount: open.count,
        partnerAddedToday: list.items.contains {
          $0.author == partner && cal.isDate($0.added, inSameDayAs: date)
        }
      )
    }

    planned = us.planned
      .filter { $0.rating == nil && $0.date >= today }
      .min { $0.date < $1.date }
      .map { plan in
        let hidden = plan.surprise && plan.organizer != couple.viewer
        return PlannedPreview(
          id: plan.id,
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

/// Picks what the smart slot shows: the first rule that holds wins.
/// note: gifts, notes and today's question rank above the mood once those features exist; they have no data yet.
public enum SmartSlot {
  public static func pick(for s: OurioSnapshot) -> WidgetModule {
    if s.planned?.isToday == true { return .date }
    if s.freshPartnerMood != nil { return .mood }
    if let next = s.next, next.daysLeft <= 3 { return .us }
    if let list = s.list, list.partnerAddedToday, list.openCount > 0 { return .list }
    return .us
  }
}

/// When the widgets need a new entry without anything being saved: a purr ends, a check-in stops being news, the
/// room turns to night or day, the day counter rolls over.
public enum WidgetTimeline {
  public static func entryDates(
    from now: Date, activity: WidgetActivity, moods: [String: MoodCheckIn],
    horizon: TimeInterval = 24 * 3600
  ) -> [Date] {
    let cal = Calendar.current
    let end = now.addingTimeInterval(horizon)
    var dates: [Date] = [now]
    if let pet = activity.lastPet {
      dates.append(pet.addingTimeInterval(WidgetActivity.purrLength))
    }
    dates += moods.values.map { $0.date.addingTimeInterval(OurioSnapshot.moodNews) }
    for hour in [0, 7, 20] {
      if let next = cal.nextDate(
        after: now, matching: DateComponents(hour: hour, minute: 0), matchingPolicy: .nextTime)
      {
        dates.append(next)
      }
    }
    return Set(dates.filter { $0 >= now && $0 <= end }).sorted()
  }
}
