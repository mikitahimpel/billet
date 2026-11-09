import SwiftUI
import Testing
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

        let pieces: [(String, CGSize, AnyView)] = [
            ("corner-large", Self.large, AnyView(Corner(snapshot: day))),
            ("mochi-medium", Self.medium, AnyView(MochiMedium(snapshot: day))),
            ("mochi-night-medium", Self.medium, AnyView(MochiMedium(snapshot: evening))),
            ("mochi-ginger-medium", Self.medium, AnyView(MochiMedium(snapshot: ginger))),
            ("us-small", Self.small, AnyView(ModuleView(module: .us, snapshot: day))),
            ("mood-small", Self.small, AnyView(ModuleView(module: .mood, snapshot: day, smart: true))),
            ("list-small", Self.small, AnyView(ModuleView(module: .list, snapshot: day))),
            ("date-small", Self.small, AnyView(ModuleView(module: .date, snapshot: day))),
            ("moment-small", Self.small, AnyView(ModuleView(module: .moment, snapshot: day))),
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
                try #require(image.pngData()).write(to: directory.appending(path: "\(name)-\(look).png"))
            }
        }
        #expect(rendered == pieces.count * 3)
    }
}

/// The large "Our Corner" widget: Mochi's room over two blocks.
private struct Corner: View {
    let snapshot: OurioSnapshot

    var body: some View {
        VStack(spacing: 0) {
            MochiRoom(snapshot: snapshot).frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 0) {
                ModuleView(module: .us, snapshot: snapshot)
                Divider()
                ModuleView(module: .list, snapshot: snapshot)
            }
            .frame(height: 158)
        }
    }
}

/// The medium "Ourio" widget: Mochi beside the smart slot.
private struct MochiMedium: View {
    let snapshot: OurioSnapshot

    var body: some View {
        HStack(spacing: 0) {
            MochiRoom(snapshot: snapshot, showsCaption: false)
            Divider()
            ModuleView(module: snapshot.smartModule, snapshot: snapshot, smart: true)
        }
    }
}
