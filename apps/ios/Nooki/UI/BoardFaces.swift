import SwiftUI
import UIKit

/// Draws the notes and doodles pinned on the corkboard as small images the board puts on planes.
enum BoardFaces {
    /// The newest `BoardRoomScene.slots` notes, newest first.
    static func pins(state: HomeState) async -> [BoardPin] {
        var pins: [BoardPin] = []
        for note in state.notes.notes.prefix(BoardRoomScene.slots) {
            let view = NoteFace(note: note, doodle: await doodle(note))
            if let face = render(view) {
                pins.append(BoardPin(id: note.id, face: face, size: [0.12, 0.12]))
            }
        }
        return pins
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

/// A note on the board: the couple's paper color, the text or the doodle, and who wrote it.
private struct NoteFace: View {
    let note: Note
    let doodle: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(hex: note.paper.hex)

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
