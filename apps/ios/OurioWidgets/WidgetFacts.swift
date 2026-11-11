import Design
import DrawInterface
import Foundation
import MoodInterface
import WidgetInterface
import Persistence
import SwiftUI
import ProfileInterface
import UIKit
import UsInterface
import WidgetKit
import Wire

/// What the family widgets draw besides the snapshot: the streak, the wallet and the partner's latest drawing, read
/// from the App Group once per timeline.
struct WidgetFacts: Equatable {
    var streak = LoveStreak()
    var wallet = Wallet()
    var drawing: LatestDrawing?

    static func load() -> WidgetFacts {
        WidgetFacts(streak: SharedFile.read(LoveStreak.self, from: "Us/streak.json") ?? LoveStreak(),
                    wallet: SharedFile.read(Wallet.self, from: "Shop/wallet.json") ?? Wallet(),
                    drawing: LatestDrawing.load())
    }

    static func sample(now: Date = .now, drawing: Bool = false) -> WidgetFacts {
        let day = Calendar.current.startOfDay(for: now)
        return WidgetFacts(streak: LoveStreak(count: 9, lastDay: day, best: 12),
                           wallet: Wallet(coins: 240, level: 4, progress: 0.6, wishlist: ["rug-moss", "lamp-star"]),
                           drawing: drawing ? .sample(now: now) : nil)
    }
}

/// How Mochi is, in one word, from what the couple did. She is never sad, whatever the couple does or doesn't do.
enum MochiPose: Equatable {
    case purring, asleep, waiting, chirpy, napping, quiet, idle

    static func pose(_ s: OurioSnapshot, drawing: LatestDrawing?) -> MochiPose {
        if s.isPurring { return .purring }
        if s.isNight { return .asleep }
        if PartnerNews.freshDrawing(s, drawing: drawing) != nil { return .waiting }
        switch s.freshPartnerMood?.mood {
        case .sleepy: return .napping
        case .happy: return .chirpy
        case .busy: return .quiet
        case .missing: return .waiting
        case nil: return .idle
        }
    }

    var word: String {
        switch self {
        case .purring: "Purring"
        case .asleep: "Asleep"
        case .waiting: "Waiting"
        case .chirpy: "Chirpy"
        case .napping: "Napping"
        case .quiet: "Keeping quiet"
        case .idle: "Sitting pretty"
        }
    }

    func line(_ s: OurioSnapshot, drawing: LatestDrawing?) -> String {
        switch self {
        case .purring: return "Love received"
        case .asleep: return "Lamps are on"
        case .waiting:
            if PartnerNews.freshDrawing(s, drawing: drawing) != nil { return "\(s.partner) drew you something" }
            return "\(s.partner) is missing you"
        case .chirpy: return "\(s.partner) is happy"
        case .napping: return "\(s.partner) is sleepy"
        case .quiet: return "\(s.partner) is busy"
        case .idle: return "Say hi"
        }
    }
}

/// The partner's newest thing to answer, a drawing or a check-in.
enum PartnerNews: Equatable {
    case drawing(LatestDrawing)
    case mood(MoodCheckIn)

    var date: Date {
        switch self {
        case .drawing(let drawing): drawing.sentAt
        case .mood(let check): check.date
        }
    }

    /// When it was sent, in words that stay true until the widget next reloads: a clock time today, never "5 min ago".
    func sentLabel(relativeTo now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(.dateTime.hour().minute()) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// How long a drawing stays news on the Home Screen.
    static let drawingNews: TimeInterval = 24 * 3600

    static func freshDrawing(_ s: OurioSnapshot, drawing: LatestDrawing?) -> PartnerNews? {
        guard let drawing else { return nil }
        let age = s.date.timeIntervalSince(drawing.sentAt)
        return age >= 0 && age < drawingNews && !drawing.strokes.isEmpty ? .drawing(drawing) : nil
    }

    /// A drawing from the last day or a check-in that is still fresh, whichever is newer; a drawing without strokes
    /// isn't news.
    static func latest(_ s: OurioSnapshot, drawing: LatestDrawing?) -> PartnerNews? {
        let drawn = freshDrawing(s, drawing: drawing)
        let felt = s.freshPartnerMood.map(PartnerNews.mood)
        switch (drawn, felt) {
        case (let drawn?, let felt?): return drawn.date >= felt.date ? drawn : felt
        case (let one?, nil), (nil, let one?): return one
        case (nil, nil): return nil
        }
    }
}

/// The flame: the streak's number, where it stands today and how far the next milestone is.
struct StreakGlance: Equatable {
    var count: Int
    var status: LoveStreak.Status
    var next: Int?
    /// 0...1 from the milestone behind to the one ahead.
    var progress: Double

    init(_ streak: LoveStreak, on date: Date) {
        status = streak.status(on: date)
        count = streak.current(on: date)
        let ahead = streak.milestone(on: date)
        next = ahead.next
        if let next = ahead.next {
            let behind = ahead.reached ?? 0
            progress = min(1, max(0, Double(count - behind) / Double(next - behind)))
        } else {
            progress = 1
        }
    }

    var toGo: Int? { next.map { $0 - count } }

    /// Today doesn't count yet and the flame goes out at midnight.
    var isAtRisk: Bool { status == .atRisk }

    var caption: String {
        switch status {
        case .cold: "Start a streak today"
        case .restorable: "Restore it in Ourio"
        case .atRisk: "Keep it today"
        case .done:
            if let toGo { "\(toGo) to \(next ?? 0)" } else { "Best streak yet" }
        }
    }
}

/// The balance and where Mochi's care stands.
struct CoinsGlance: Equatable {
    var coins: Int
    var level: Int
    var progress: Double
    var wished: Int

    init(_ wallet: Wallet) {
        coins = wallet.coins
        level = wallet.level
        progress = min(1, max(0, wallet.progress))
        wished = wallet.wishlist.count
    }

    var caption: String {
        if wished > 0 { return wished == 1 ? "1 on your wishlist" : "\(wished) on your wishlist" }
        return coins == 0 ? "Earn coins by caring" : "Treat the room"
    }
}

/// When the family widgets draw a new entry without anything being saved, kept sparse: the system budgets a widget
/// to a few dozen reloads a day, and every entry here is a moment the picture changes.
enum FamilyTimeline {
    /// The closest two entries may be, apart from the purr ending.
    static let minimumGap: TimeInterval = 10 * 60

    static func entryDates(from now: Date, activity: WidgetActivity, moods: [String: MoodCheckIn],
                           drawing: LatestDrawing?) -> [Date] {
        var dates = WidgetTimeline.entryDates(from: now, activity: activity, moods: moods)
        if let drawing { dates.append(drawing.sentAt.addingTimeInterval(PartnerNews.drawingNews)) }
        let purrEnd = activity.lastPet?.addingTimeInterval(WidgetActivity.purrLength)
        var kept: [Date] = []
        for date in dates.filter({ $0 >= now }).sorted() {
            if let last = kept.last, date.timeIntervalSince(last) < minimumGap, date != purrEnd { continue }
            kept.append(date)
        }
        return kept
    }
}

/// Whether the viewer's own check-in today is the hug.
enum HugState {
    static func sent(_ s: OurioSnapshot) -> Bool {
        guard let mine = s.myMood else { return false }
        return mine.mood == .missing && Calendar.current.isDate(mine.date, inSameDayAs: s.date)
    }
}

struct FamilyEntry: TimelineEntry {
    let date: Date
    let snapshot: OurioSnapshot
    let facts: WidgetFacts
    let momentImage: Data?
    let momentDate: Date?
}


extension OurioSnapshot {
    /// Gallery and placeholder data: a plausible evening, nothing from the couple's real stores.
    static func sample(now: Date = .now) -> OurioSnapshot {
        let cal = Calendar.current
        return OurioSnapshot(
            date: now, viewer: "L", partner: "M", daysTogether: 127,
            next: NextEvent(title: "4 months together", icon: .init(symbol: "sparkles", tint: .sun),
                            date: cal.date(byAdding: .day, value: 18, to: now) ?? now, daysLeft: 18),
            partnerMood: MoodCheckIn(mood: .missing, date: now.addingTimeInterval(-1200)),
            myMood: nil,
            list: ListPreview(id: UUID(), title: "Groceries", icon: ListKind.groceries.icon,
                              items: [.init(id: UUID(), text: "Oat milk", author: "M", done: false),
                                      .init(id: UUID(), text: "Cat treats", author: "L", done: false),
                                      .init(id: UUID(), text: "Lemons", author: "M", done: true)],
                              openCount: 2, partnerAddedToday: false),
            planned: nil,
            idea: IdeaPreview(id: 1, title: "Blanket fort cinema", pitch: "Build a fort, pick a movie, no phones allowed inside",
                              matched: true),
            moment: nil, isPurring: false, isNight: isNight(now))
    }
}

extension LatestDrawing {
    /// Two loose strokes, for the gallery and the previews.
    static func sample(now: Date = .now) -> LatestDrawing {
        LatestDrawing(
            noteID: "sample", seq: 1, sentAt: now.addingTimeInterval(-600),
            compact: CompactStrokes(strokes: [
                CompactStroke(color: "#7B4FE0", width: 32, points: [120, 300, 300, 160, 520, 320, 700, 180, 880, 340]),
                CompactStroke(color: "#FF8FA3", width: 32, points: [300, 520, 500, 640, 700, 520]),
            ]),
            paper: .sky)
    }
}

extension FamilyEntry {
    /// What the in-app gallery and the placeholder draw: a plausible afternoon, nothing from the couple's stores.
    static func sample(now: Date = .now, mood: PartnerMood? = .missing, drawing: Bool = false, photo: Bool = false,
                       purring: Bool = false) -> FamilyEntry {
        var snapshot = OurioSnapshot.sample(now: now)
        snapshot.partnerMood = mood.map { MoodCheckIn(mood: $0, date: now.addingTimeInterval(-1200)) }
        snapshot.isPurring = purring
        return FamilyEntry(date: now, snapshot: snapshot, facts: .sample(now: now, drawing: drawing),
                           momentImage: photo ? SamplePhoto.jpeg() : nil,
                           momentDate: photo ? now.addingTimeInterval(-40 * 86_400) : nil)
    }
}

/// A warm gradient standing in for a photo.
enum SamplePhoto {
    static func jpeg() -> Data? {
        UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300)).jpegData(withCompressionQuality: 0.8) { context in
            let colors = [UIColor(Color(hex: 0xFAB380)).cgColor, UIColor(Color(hex: 0x7399CC)).cgColor]
            guard let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: [0, 1]) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 300, y: 300), options: [])
        }
    }
}
