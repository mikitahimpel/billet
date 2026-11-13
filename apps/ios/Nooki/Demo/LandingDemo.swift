#if DEBUG
import FeatureUs
import Foundation
import MomentsInterface
import Persistence
import ProfileInterface
import ShopInterface
import SwiftUI
import Transport
import UIKit
import UsInterface
import Wire

/// A made-up couple for the landing page's screenshots: `-landingDemo YES` fills the phone's stores with Alex and Sam,
/// a few drawn pictures, a film list and a calendar, and `-landingGo <screen>` opens one screen. Compiled in Debug
/// builds only.
enum LandingDemo {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "landingDemo") }

    /// The Pick tonight screen's room, answered in memory.
    static let server: LandingDemoServer? = isOn ? LandingDemoServer() : nil

    /// The lock-screen canvas shows this time instead of the real one.
    static var clock: Date {
        Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: .now) ?? .now
    }

    private static func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    /// Before the stores are built: the streak file is read once when its store starts.
    static func prepare() {
        guard isOn else { return }
        let today = Calendar.current.startOfDay(for: .now)
        SharedFile.write(LoveStreak(count: 23, lastDay: today, best: 41), to: StreakStore.file)
        SharedFile.flush()
    }

    @MainActor
    static func seed(profile: CoupleStore, wallet: WalletStore, moments: MomentStore, us: UsStore) {
        guard isOn else { return }
        profile.update(names: ["L": "Alex", "M": "Sam"], togetherSince: day(-126))
        profile.adopt(pairID: "demo-pair", me: "demo-alex", partner: "demo-sam")
        wallet.update { $0.coins = 64 }
        if moments.moments.isEmpty { seedMoments(moments) }
        if us.events.isEmpty { seedCalendar(us) }
        if let watch = us.lists.first(where: { $0.kind == .watch }), watch.items.isEmpty { seedFilms(us, watch.id) }
    }

    @MainActor
    private static func seedMoments(_ moments: MomentStore) {
        let scenes: [(Int, String, String, Int, Bool)] = [
            (0, "Sunset at the pier", "M", -2, true), (1, "Sunday pancakes", "L", -6, false),
            (2, "Last train home", "M", -11, true), (3, "Picnic by the lake", "L", -19, false),
            (4, "First snow", "M", -33, true),
        ]
        for (scene, caption, author, offset, loved) in scenes.reversed() {
            let date = Calendar.current.date(byAdding: .hour, value: 14, to: day(offset)) ?? .now
            if let moment = moments.add(photo(scene), caption: caption, author: author, date: date), loved {
                moments.toggleLove(moment)
            }
        }
    }

    @MainActor
    private static func seedCalendar(_ us: UsStore) {
        let glyphs = UsGlyph.palette
        us.upsertEvent(UsEvent(title: "Anniversary dinner", icon: glyphs[0], date: day(18)))
        us.upsertEvent(UsEvent(title: "Weekend by the sea", icon: glyphs[3], date: day(33)))
        us.upsertEvent(UsEvent(title: "Sam's birthday", icon: glyphs[2], date: day(52), yearly: true, owner: nil))
    }

    @MainActor
    private static func seedFilms(_ us: UsStore, _ list: UUID) {
        let films: [(String, Int, Int)] = [
            ("Spirited Away", 129, 2001), ("Paddington 2", 346648, 2017), ("La La Land", 313369, 2016),
            ("Little Women", 331482, 2019), ("The Princess Bride", 2493, 1987),
        ]
        for (index, film) in films.enumerated() {
            us.addItem(film.0, to: list, author: index.isMultiple(of: 2) ? "L" : "M",
                       media: ItemMedia(kind: .movie, tmdb: film.1, year: film.2))
        }
    }

    // MARK: Pictures

    private struct Scene {
        let sky: [UInt32]
        let sun: UInt32
        let far: UInt32
        let near: UInt32
    }

    private static let scenes = [
        Scene(sky: [0x2B2A5E, 0xE0697B, 0xF7B267], sun: 0xFFE3A3, far: 0x3A3568, near: 0x1F2147),
        Scene(sky: [0x9CC9E8, 0xF6E7C8], sun: 0xFFF1B8, far: 0x8DBA7C, near: 0x5E9A62),
        Scene(sky: [0x0E1230, 0x2B2F63], sun: 0xF3EBD0, far: 0x1B1F45, near: 0x0A0C20),
        Scene(sky: [0xF8D9B0, 0xF1B995], sun: 0xFFFFFF, far: 0xC8E0A8, near: 0x7FB77E),
        Scene(sky: [0xB7C9E6, 0xEAF0F8], sun: 0xFFFFFF, far: 0xDDE6F2, near: 0xF7FAFF),
    ]

    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(cgColor: CGColor(
            srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1))
    }

    /// A small painted scene with two figures, for a photo.
    static func photo(_ index: Int) -> UIImage {
        let scene = scenes[index % scenes.count]
        let size = index.isMultiple(of: 2) ? CGSize(width: 1200, height: 900) : CGSize(width: 900, height: 1200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = scene.sky.map { color($0).cgColor } as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: nil) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height * 0.75), options: [])
            }
            color(scene.sun).setFill()
            let radius = size.width * 0.11
            cg.fillEllipse(in: CGRect(x: size.width * 0.68 - radius, y: size.height * 0.34 - radius,
                                      width: radius * 2, height: radius * 2))
            color(scene.far).setFill()
            cg.fillEllipse(in: CGRect(x: -size.width * 0.2, y: size.height * 0.58, width: size.width * 0.9, height: size.height * 0.5))
            cg.fillEllipse(in: CGRect(x: size.width * 0.35, y: size.height * 0.64, width: size.width * 0.9, height: size.height * 0.5))
            color(scene.near).setFill()
            cg.fillEllipse(in: CGRect(x: -size.width * 0.3, y: size.height * 0.78, width: size.width * 1.6, height: size.height * 0.5))
            let figure = color(0x14101C).withAlphaComponent(0.55)
            figure.setFill()
            let base = size.height * 0.8
            for (offset, tall) in [(0.0, 1.0), (0.085, 0.88)] {
                let x = size.width * (0.42 + offset)
                let height = size.height * 0.12 * tall
                cg.fillEllipse(in: CGRect(x: x - 22, y: base - height - 46, width: 44, height: 44))
                cg.fillEllipse(in: CGRect(x: x - 30, y: base - height, width: 60, height: (height + 40) * 1.4))
            }
        }
    }

    // MARK: The drawing

    /// A heart, stars and a squiggle, in unit-width coordinates, as a hand would draw them.
    static func drawing() -> [Stroke] {
        func line(_ color: UInt32, _ width: Double, _ points: [(Double, Double)]) -> Stroke {
            Stroke(color: PaletteInk.wire(color), width: width, points: points.map { Point(x: $0.0, y: $0.1) })
        }
        func around(_ cx: Double, _ cy: Double, _ r: Double, steps: Int = 60, _ f: (Double) -> (Double, Double)) -> [(Double, Double)] {
            (0...steps).map { i in
                let (x, y) = f(Double(i) / Double(steps) * 2 * .pi)
                return (cx + x * r, cy + y * r)
            }
        }
        let heart = around(0.5, 1.0, 0.0125) { (t: Double) -> (Double, Double) in
            let x: Double = 16 * pow(sin(t), 3)
            let a: Double = 13 * cos(t) - 5 * cos(2 * t)
            let b: Double = 2 * cos(3 * t) + cos(4 * t)
            return (x, -(a - b))
        }
        func star(_ cx: Double, _ cy: Double, _ r: Double) -> [(Double, Double)] {
            (0...10).map { i in
                let angle = Double(i) * .pi / 5 - .pi / 2
                let radius = i.isMultiple(of: 2) ? r : r * 0.45
                return (cx + cos(angle) * radius, cy + sin(angle) * radius)
            }
        }
        let squiggle = (0...50).map { i -> (Double, Double) in
            let t = Double(i) / 50
            return (0.2 + 0.6 * t, 1.3 + 0.025 * sin(t * 6 * .pi))
        }
        let ears = [(0.43, 0.8), (0.445, 0.74), (0.475, 0.78), (0.525, 0.78), (0.555, 0.74), (0.57, 0.8)]
        return [
            line(0xFF8FAB, 0.032, heart),
            line(0xF2CF5B, 0.022, star(0.22, 0.88, 0.05)),
            line(0xF2CF5B, 0.022, star(0.8, 0.84, 0.04)),
            line(0x7CC4FF, 0.022, squiggle),
            line(0xFFFFFF, 0.02, ears),
            line(0xFFFFFF, 0.02, around(0.5, 0.84, 0.07, steps: 40) { (t: Double) -> (Double, Double) in (cos(t), sin(t) * 0.9) }),
        ]
    }
}

/// Stands in for the server's session on the Us tab: paired, with a Pick tonight room whose partner has swiped.
@MainActor
final class LandingDemoServer: UsServer {
    let api = APIClient.offline
    let baseURL = URL(string: "https://demo.invalid")!
    let isPaired = true
    let hasFinishedSignIn = true
    let titles: TitleSource? = nil
    var matches: (@MainActor (PickMatch) -> Void)?

    var pickTonight: PickTonightSync? {
        PickTonightSync(
            fetch: { () async throws(TransportError) in PickTonightResponse(partnerPicked: 3) },
            swipe: { (request) async throws(TransportError) in
                guard request.choice == .want else { return PickTonightResponse(partnerPicked: 3) }
                let match = PickMatch(
                    title: request.title, name: request.name, posterPath: nil,
                    at: Int(Date.now.timeIntervalSince1970 * 1000))
                return PickTonightResponse(partnerPicked: 3, matches: [match], match: match)
            })
    }

    func pairingSheet() -> AnyView { AnyView(EmptyView()) }
}
#endif
