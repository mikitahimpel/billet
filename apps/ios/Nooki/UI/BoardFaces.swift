import FeatureStory
import MomentsInterface
import StoryInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import Design
import UIKit
import UsInterface

enum BoardFaces {
    /// The newest `BoardRoomScene.slots` cards, newest first: the notes and doodles, and the photos pinned to the wall
    /// as polaroids.
    static func pins(state: HomeState, paired: Bool) async -> [BoardPin] {
        enum Card { case note(Note), photo(Moment) }
        let cards = (state.notes.notes.map { (date: $0.date, card: Card.note($0)) }
            + state.moments.pinned.map { (date: $0.date, card: Card.photo($0)) })
            .sorted { $0.date > $1.date }
            .prefix(BoardRoomScene.slots - CasePin.count(state.story.state))

        var pins: [BoardPin] = CasePin.pins(state.story.state, cat: state.petName,
                                            partner: state.profile.name(of: state.otherPartner))
        for (_, card) in cards {
            switch card {
            case .note(let note):
                let unsent = UnsentMark.shows(note.unsent, paired: paired)
                let author = state.profile.name(of: note.author)
                let key = "note \(note.id) \(note.hashValue) \(unsent) \(author)" as NSString
                var face = faces.object(forKey: key)
                if face == nil {
                    face = render(NoteFace(note: note, author: author, doodle: await doodle(note), unsent: unsent),
                                  as: key)
                }
                if let face {
                    pins.append(BoardPin(id: note.id, face: face, size: [0.12, 0.12]))
                }
            case .photo(let moment):
                let byline = state.profile.byline(of: moment)
                let key = "photo \(moment.id) \(moment.file) \(moment.caption) \(byline)" as NSString
                var face = faces.object(forKey: key)
                if face == nil {
                    guard let photo = await state.moments.filmPrint(for: moment, maxPixels: MomentStore.wallPixels)
                    else { continue }
                    face = render(Polaroid(width: 240, caption: moment.caption, byline: byline, lifted: false) {
                        Image(uiImage: photo).resizable().scaledToFill()
                    }, as: key)
                }
                if let face {
                    let width: Float = 0.12
                    pins.append(BoardPin(id: moment.id, face: face,
                                         size: [width, width * Float(face.size.height / face.size.width)]))
                }
            }
        }
        return pins
    }

    static func key(state: HomeState, paired: Bool) -> [String] {
        CasePin.key(state.story.state) + state.notes.notes.prefix(BoardRoomScene.slots - CasePin.count(state.story.state)).map {
            let unsent = UnsentMark.shows($0.unsent, paired: paired) ? " unsent" : ""
            return "\($0.id)\(unsent) \(state.profile.name(of: $0.author))"
        }
            + state.moments.pinned.map { "\($0.id)\($0.caption) \(state.profile.byline(of: $0))" }
    }

    private static func doodle(_ note: Note) async -> UIImage? {
        guard let url = NoteStore.doodleURL(for: note) else { return nil }
        return await Task.detached(priority: .userInitiated) { Downsample.image(at: url, maxPixels: 480) }.value
    }

    /// Faces already drawn, by everything that shows on them: a new note or caption redraws only its own card, each
    /// a main-thread rasterization.
    private static let faces = NSCache<NSString, UIImage>()

    private static func render<V: View>(_ view: V, as key: NSString) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let face = renderer.uiImage else { return nil }
        faces.setObject(face, forKey: key)
        return face
    }
}

private struct NoteFace: View {
    let note: Note
    let author: String
    let doodle: UIImage?
    let unsent: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PaperSheet(color: Color(hex: note.paper.hex), cornerRadius: 0)

            if let doodle {
                Image(uiImage: doodle).resizable().scaledToFit().padding(Space.m)
            } else {
                Text(note.text)
                    .font(.custom("Noteworthy-Bold", size: 26))
                    .foregroundStyle(Color(hex: note.inkHex))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.45)
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: Space.xs) {
                if unsent { UnsentMark(size: 14) }
                Text("— \(author)")
                    .font(.custom("Noteworthy-Bold", size: 15))
            }
            .foregroundStyle(Color(hex: note.inkHex).opacity(0.7))
            .padding(10)
        }
        .frame(width: 240, height: 240)
        .postage(of: note, width: 240)
    }
}
