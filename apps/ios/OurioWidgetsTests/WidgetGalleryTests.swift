import DrawInterface
import MomentsInterface
import MoodInterface
import ShopInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import UIKit
import Testing
import UsInterface
import WidgetKit
import Wire

/// Renders the widgets' views into `BILLET_SAMPLES` when set (CI keeps the PNGs as the `samples` artifact): light,
/// dark and accented. Without WidgetKit the container background is drawn here and the system tint is not applied,
/// so the accented shots show only what each view leaves out or keeps.
@MainActor
struct WidgetGalleryTests {
    static let small = CGSize(width: 170, height: 170)
    static let medium = CGSize(width: 364, height: 170)
    static let large = CGSize(width: 364, height: 382)
    static let seSmall = CGSize(width: 141, height: 141)
    static let seMedium = CGSize(width: 292, height: 141)
    static let seLarge = CGSize(width: 292, height: 311)

    /// A warm gradient standing in for a photo.
    static func photo() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300))
        return renderer.jpegData(withCompressionQuality: 0.8) { context in
            let colors = [UIColor(red: 0.98, green: 0.7, blue: 0.5, alpha: 1).cgColor,
                          UIColor(red: 0.45, green: 0.6, blue: 0.8, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 300, y: 300), options: [])
        }
    }

    /// An afternoon, so the room is lit, and the same evening, when it is night.
    static let afternoon = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: .now) ?? .now
    static let night = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: .now) ?? .now

    @Test func rendersTheGallery() throws {
        let day = OurioSnapshot.sample(now: Self.afternoon)
        let evening = OurioSnapshot.sample(now: Self.night)
        var ginger = day
        ginger.catAvatar = "MochiPortrait-ginger"
        let drawing = DrawingEntry(
            date: .now,
            drawing: LatestDrawing(
                noteID: "n", seq: 1, sentAt: .now.addingTimeInterval(-600),
                compact: CompactStrokes(strokes: [
                    CompactStroke(color: "#7B4FE0", width: 32, points: [120, 300, 300, 160, 520, 320, 700, 180, 880, 340]),
                    CompactStroke(color: "#FF8FA3", width: 32, points: [300, 520, 500, 640, 700, 520]),
                ]),
                paper: .sky),
            partner: "M")

        let facts = WidgetFacts(
            streak: LoveStreak(count: 9, lastDay: Calendar.current.startOfDay(for: .now), best: 12),
            wallet: Wallet(coins: 240, level: 4, progress: 0.6, wishlist: ["rug-moss", "lamp-star"]),
            drawing: nil)
        let drawn = WidgetFacts(streak: facts.streak, wallet: facts.wallet, drawing: drawing.drawing)
        func entry(_ snapshot: OurioSnapshot, _ facts: WidgetFacts, photo: Bool = false,
                   want: CatNeedsGlance.Want? = nil) -> FamilyEntry {
            FamilyEntry(date: snapshot.date, snapshot: snapshot, facts: facts, momentImage: photo ? Self.photo() : nil,
                        momentDate: photo ? snapshot.date.addingTimeInterval(-40 * 86_400) : nil, want: want)
        }
        var waiting = day
        waiting.partnerMood = MoodCheckIn(mood: .missing, date: day.date.addingTimeInterval(-600))
        var purring = day
        purring.isPurring = true
        let empty = WidgetFacts()

        var pieces: [(String, CGSize, AnyView)] = []
        for (device, small, medium, large) in [
            ("pm", Self.small, Self.medium, Self.large), ("se", Self.seSmall, Self.seMedium, Self.seLarge),
        ] {
            let sizes: [(String, CGSize, WidgetFamily)] = [
                ("small", small, .systemSmall), ("medium", medium, .systemMedium), ("large", large, .systemLarge),
            ]
            for (label, size, family) in sizes {
                func add(_ name: String, _ entry: FamilyEntry, _ view: (FamilyEntry, WidgetFamily) -> AnyView) {
                    pieces.append(("\(name)-\(label)-\(device)", size, AnyView(view(entry, family))))
                }
                add("mochi", entry(waiting, drawn)) { AnyView(MochiFamilyView(entry: $0, family: $1)) }
                if device == "pm" {
                    add("mochi-night", entry(evening, facts)) { AnyView(MochiFamilyView(entry: $0, family: $1)) }
                    add("mochi-purring", entry(purring, facts)) { AnyView(MochiFamilyView(entry: $0, family: $1)) }
                    add("mochi-hungry", entry(day, facts, want: .food)) { AnyView(MochiFamilyView(entry: $0, family: $1)) }
                    add("mochi-cuddly", entry(day, facts, want: .love)) { AnyView(MochiFamilyView(entry: $0, family: $1)) }
                    add("mochi-sleepy", entry(day, facts, want: .rest)) { AnyView(MochiFamilyView(entry: $0, family: $1)) }
                    add("mochi-playful", entry(day, facts, want: .play)) { AnyView(MochiFamilyView(entry: $0, family: $1)) }
                    add("mochi-cold", entry(day, empty, want: .food)) { AnyView(MochiFamilyView(entry: $0, family: $1)) }
                    add("us-cold", entry(day, empty)) { AnyView(UsFamilyView(entry: $0, family: $1)) }
                } else {
                    // The largest type a widget allows, on the smallest screen.
                    func large(_ view: some View) -> AnyView {
                        AnyView(view.environment(\.dynamicTypeSize, .accessibility3).widgetTypeCap())
                    }
                    pieces.append(("mochi-hungry-xl-\(label)-\(device)", size,
                                   large(MochiFamilyView(entry: entry(day, facts, want: .food), family: family))))
                    pieces.append(("us-xl-\(label)-\(device)", size, large(UsFamilyView(entry: entry(day, facts), family: family))))
                    if family != .systemLarge {
                        pieces.append(("partner-xl-\(label)-\(device)", size,
                                       large(PartnerFamilyView(entry: entry(day, drawn), family: family))))
                        pieces.append(("coins-xl-\(label)-\(device)", size,
                                       large(CoinsFamilyView(entry: entry(day, facts), family: family))))
                    } else {
                        pieces.append(("day-xl-\(label)-\(device)", size,
                                       large(DayFamilyView(entry: entry(waiting, drawn), family: family))))
                    }
                }
                add("us", entry(day, facts)) { AnyView(UsFamilyView(entry: $0, family: $1)) }
                if family != .systemLarge {
                    add("partner", entry(day, drawn)) { AnyView(PartnerFamilyView(entry: $0, family: $1)) }
                    add("partner-mood", entry(waiting, facts)) { AnyView(PartnerFamilyView(entry: $0, family: $1)) }
                    add("partner-empty", entry(day, empty)) { AnyView(PartnerFamilyView(entry: $0, family: $1)) }
                    add("coins", entry(day, facts)) { AnyView(CoinsFamilyView(entry: $0, family: $1)) }
                }
                add("memory", entry(day, facts, photo: true)) { AnyView(MemoryFamilyView(entry: $0, family: $1)) }
                if family == .systemLarge {
                    add("day", entry(waiting, drawn)) { AnyView(DayFamilyView(entry: $0, family: $1)) }
                    add("day-hungry", entry(day, drawn, want: .food)) { AnyView(DayFamilyView(entry: $0, family: $1)) }
                }
            }
        }
        for (device, circular, rectangular, inline) in [
            ("pm", CGSize(width: 76, height: 76), CGSize(width: 172, height: 76), CGSize(width: 260, height: 22)),
            ("se", CGSize(width: 72, height: 72), CGSize(width: 157, height: 72), CGSize(width: 230, height: 22)),
        ] {
            let sizes: [(String, CGSize, WidgetFamily)] = [
                ("circular", circular, .accessoryCircular), ("rectangular", rectangular, .accessoryRectangular),
                ("inline", inline, .accessoryInline),
            ]
            for (label, size, family) in sizes {
                let e = entry(waiting, drawn)
                pieces.append(("lock-us-\(label)-\(device)", size, AnyView(UsLockView(entry: e, family: family))))
                pieces.append(("lock-streak-\(label)-\(device)", size, AnyView(StreakLockView(entry: e, family: family))))
                pieces.append(("lock-cat-\(label)-\(device)", size, AnyView(CatLockView(entry: e, family: family))))
                pieces.append(("lock-cat-hungry-\(label)-\(device)", size,
                               AnyView(CatLockView(entry: entry(day, drawn, want: .food), family: family))))
                pieces.append(("lock-partner-\(label)-\(device)", size, AnyView(PartnerLockView(entry: e, family: family))))
            }
        }
        for module in WidgetModule.allCases {
            for (label, size) in [("small", Self.small), ("medium", Self.medium), ("small-se", Self.seSmall)] {
                pieces.append(("block-\(module.rawValue)-\(label)", size,
                               AnyView(ModuleView(module: module, snapshot: day, momentImage: Self.photo()))))
            }
        }
        pieces += [
            ("block-small", Self.small, AnyView(ModuleView(module: .mood, snapshot: day, smart: true))),
            ("drawing-small", Self.small, AnyView(DrawingWidgetView(entry: drawing))),
        ]

        var rendered = 0
        for (name, size, view) in pieces {
            for (look, scheme, mode) in [
                ("light", ColorScheme.light, WidgetRenderingMode.fullColor), ("dark", .dark, .fullColor),
                ("accented", .dark, .accented),
            ] {
                let shot = view
                    .frame(width: size.width, height: size.height)
                    .background(mode == .fullColor ? WidgetGallery.background : Color(white: 0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(12)
                    .background(scheme == .dark ? Color(white: 0.08) : Color(white: 0.93))
                    .environment(\.colorScheme, scheme)
                    .environment(\.widgetRenderingMode, mode)
                let renderer = ImageRenderer(content: shot)
                renderer.scale = 2
                let image = try #require(renderer.uiImage)
                #expect(image.size.width == size.width + 24)
                rendered += 1

                guard let folder = ProcessInfo.processInfo.environment["BILLET_SAMPLES"] else { continue }
                let directory = URL(fileURLWithPath: folder, isDirectory: true).appending(path: "widgets")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let png = try #require(SamplePNG.encode(image), "\(name)-\(look): no PNG for a \(image.size) image")
                try png.write(to: directory.appending(path: "\(name)-\(look).png"))
            }
        }
        #expect(rendered == pieces.count * 3)
    }
}
