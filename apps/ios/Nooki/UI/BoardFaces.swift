import SwiftUI
import UIKit

/// Draws the notes and doodles pinned on the corkboard as small images the board puts on planes.
enum BoardFaces {
    /// The newest `BoardRoomScene.slots` cards, newest first: the notes and doodles, and the photos pinned to the wall
    /// as polaroids.
    static func pins(state: HomeState) async -> [BoardPin] {
        enum Card { case note(Note), photo(Moment) }
        let cards = (state.notes.notes.map { (date: $0.date, card: Card.note($0)) }
            + state.moments.pinned.map { (date: $0.date, card: Card.photo($0)) })
            .sorted { $0.date > $1.date }
            .prefix(BoardRoomScene.slots)

        var pins: [BoardPin] = []
        for (_, card) in cards {
            switch card {
            case .note(let note):
                if let face = render(NoteFace(note: note, doodle: await doodle(note))) {
                    pins.append(BoardPin(id: note.id, face: face, size: [0.12, 0.12]))
                }
            case .photo(let moment):
                guard let photo = await state.moments.filmPrint(for: moment, maxPixels: MomentStore.wallPixels) else { continue }
                let polaroid = Polaroid(width: 240, caption: moment.caption, byline: state.profile.byline(of: moment), lifted: false) {
                    Image(uiImage: photo).resizable().scaledToFill()
                }
                if let face = render(polaroid) {
                    let width: Float = 0.12
                    pins.append(BoardPin(id: moment.id, face: face,
                                         size: [width, width * Float(face.size.height / face.size.width)]))
                }
            }
        }
        return pins
    }

    /// Changes whenever a card on the board would.
    static func key(state: HomeState) -> [String] {
        state.notes.notes.prefix(BoardRoomScene.slots).map(\.id.uuidString)
            + state.moments.pinned.map { "\($0.id)\($0.caption)" }
    }

    private static func doodle(_ note: Note) async -> UIImage? {
        guard let url = NoteStore.doodleURL(for: note) else { return nil }
        return await Task.detached(priority: .userInitiated) { Downsample.image(at: url, maxPixels: 480) }.value
    }

    private static func render<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }
}

/// A note on the board: the couple's paper color with the prints' grain, the text or the doodle, and who wrote it.
private struct NoteFace: View {
    let note: Note
    let doodle: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PaperSheet(color: Color(hex: note.paper.hex), cornerRadius: 0)

            if let doodle {
                Image(uiImage: doodle).resizable().scaledToFit().padding(12)
            } else {
                Text(note.text)
                    .font(.custom("Noteworthy-Bold", size: 26))
                    .foregroundStyle(Color(hex: 0x5B3A28))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.45)
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Text("— \(note.author)")
                .font(.custom("Noteworthy-Bold", size: 15))
                .foregroundStyle(Color(hex: 0x5B3A28).opacity(0.7))
                .padding(10)
        }
        .frame(width: 240, height: 240)
    }
}
