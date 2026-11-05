import SwiftUI
import Testing
@testable import Billet

/// Renders the polaroid look at iPhone SE width, light and dark, into `BILLET_SAMPLES` when it is set (CI sets it and
/// keeps the PNGs as the `samples` artifact), so the look can be reviewed without a Simulator session.
struct PolaroidLookTests {
    @Test func rendersTheFeedLookInLightAndDark() throws {
        let photos = try ["CatColor-ginger", "CatStandingColor-calico", "CatColor-tuxedo", "CatStandingColor-cream"].map {
            let url = try #require(Bundle.main.url(forResource: $0, withExtension: "jpg"))
            return try #require(Downsample.image(at: url, maxPixels: 512))
        }
        let prints = try photos.map { try #require(InstantFilm.develop($0)) }

        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: LookSheet(raw: photos[0], prints: prints)
                .environment(\.colorScheme, scheme))
            renderer.scale = 2
            let image = try #require(renderer.uiImage)
            #expect(image.size.width == 375)

            guard let folder = ProcessInfo.processInfo.environment["BILLET_SAMPLES"] else { continue }
            let directory = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try #require(image.pngData())
            try data.write(to: directory.appending(path: "polaroid-\(scheme == .dark ? "dark" : "light").png"))
        }
    }
}

/// The feed as it sits on the screen: two loose columns of prints, one taped, and an ungraded photo for comparison.
private struct LookSheet: View {
    let raw: UIImage
    let prints: [UIImage]

    @Environment(\.colorScheme) private var scheme

    private let width: CGFloat = (375 - 32 - 14) / 2

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Moments")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(scheme == .dark ? Color.white : Color(hex: 0x3A2114))
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: -width * 0.05) {
                    card(prints[0], "sunday with Mochi", "Anya · Nov 5", id: 1, taped: true)
                    card(prints[2], "", "Lev · Nov 2", id: 3)
                }
                VStack(spacing: -width * 0.05) {
                    card(prints[1], "our first coffee", "Lev · Nov 4", id: 2)
                    card(prints[3], "the long walk home", "Anya · Oct 30", id: 4)
                }
                .padding(.top, width * 0.3)
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 6) {
                    Polaroid(width: width, caption: "no grade", byline: "original") { photo(raw) }
                    label("Original")
                }
                VStack(spacing: 6) {
                    Polaroid(width: width, caption: "instant film", byline: "graded") { photo(prints[0]) }
                    label("Instant film")
                }
            }
        }
        .padding(16)
        .frame(width: 375)
        .background(scheme == .dark ? Color(hex: 0x2A1A12) : Color(hex: 0xFBF3E8))
    }

    private func card(_ image: UIImage, _ caption: String, _ byline: String, id: Int, taped: Bool = false) -> some View {
        let b = { (n: Int) in UInt8(truncatingIfNeeded: n) }
        let uuid = UUID(uuid: (b(id), 0, 0, 0, b(id * 37), b(id * 71), b(id), 0, 0, 0, 0, 0, 0, 0, 0, 0))
        return Polaroid(width: width, caption: caption, byline: byline) { photo(image) }
            .overlay(alignment: .top) {
                if taped {
                    WashiTape(tone: uuid.tapeTone, width: width * 0.34).rotationEffect(.degrees(-4)).offset(y: -width * 0.06)
                }
            }
            .rotationEffect(uuid.polaroidTilt)
            .padding(.vertical, width * 0.04)
    }

    private func photo(_ image: UIImage) -> some View {
        Image(uiImage: image).resizable().scaledToFill()
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(scheme == .dark ? Color.white.opacity(0.7) : Color(hex: 0x7A5A45))
    }
}
