import Ink
import MomentsInterface
import Observation
import ShopInterface
import WidgetInterface
import WidgetUI
import PencilKit
import SwiftUI
import UIKit
import UsInterface
import Wire

@MainActor
@Observable
final class ComposerModel {
    var text = ""
    var paper: Note.Paper = .butter
    var kind: PaperKind
    var ink = PaletteInk.free
    var stamp: NoteStamp?
    var seal: NoteSeal?
    /// True while the finger draws; false while it types.
    var drawing: Bool
    private(set) var hasInk = false
    /// Stickers on the paper, under the ink. Nothing puts one here yet.
    var decorations: [Decoration] = []
    @ObservationIgnored let canvas = PKCanvasView()

    static let font = "Noteworthy-Bold"
    private static let side: CGFloat = 560

    init(kind: PaperKind, drawing: Bool) {
        self.kind = kind
        self.drawing = drawing
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasInk && decorations.isEmpty }

    func inkChanged(_ drawing: PKDrawing) { hasInk = !drawing.strokes.isEmpty }

    func undo() { canvas.undoManager?.undo() }

    func clear() {
        canvas.drawing = PKDrawing()
        hasInk = false
    }

    /// Text alone stays a text note for the partner; anything drawn is a picture of the whole note. A stamp or seal
    /// the pair hasn't unlocked (`owned`, as the Shop last heard it) stays off the note.
    func save(into journal: Journal, size: CGSize, owned: Set<String>) -> Bool {
        dropLocked(owned: owned)
        guard hasInk || !decorations.isEmpty else {
            return journal.addNote(text: text, paper: paper, ink: ink.light, stamp: stamp, seal: seal)
        }
        return journal.addNote(
            doodle: picture(size: size), compact: Self.compact(canvas.drawing, canvas: size), paper: paper,
            stamp: stamp, seal: seal)
    }

    /// The strokes in the unit square of the canvas's width, as a drawing travels; what the budget can't carry is left
    /// to the picture sent with them.
    static func compact(_ drawing: PKDrawing, canvas: CGSize) -> CompactStrokes {
        guard canvas.width > 0 else { return CompactStrokes(strokes: []) }
        let strokes = drawing.strokes.compactMap { stroke -> Stroke? in
            let points = stroke.path.interpolatedPoints(by: .distance(2)).map { point in
                let location = point.location.applying(stroke.transform)
                return Point(x: location.x / canvas.width, y: location.y / canvas.width)
            }
            guard !points.isEmpty else { return nil }
            let width = (stroke.path.first?.size.width ?? 4) / canvas.width
            return Stroke(color: hex(stroke.ink.color), width: width, points: points)
        }
        return (try? InkEncoder.encodeKeepingWhatFits(strokes)) ?? CompactStrokes(strokes: [])
    }

    private static func hex(_ color: UIColor) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let byte = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
    }

    /// Takes off the paper a stamp or seal the pair doesn't own, such as one whose unlock the server refused.
    func dropLocked(owned: Set<String>) {
        if let stamp, !NotePostage(stamp).isOwned(owned) { self.stamp = nil }
        if let seal, !NotePostage(seal).isOwned(owned) { self.seal = nil }
    }

    /// The strokes over the text, on a transparent square so the board's paper shows through.
    private func picture(size: CGSize) -> UIImage {
        let fit = min(Self.side / size.width, Self.side / size.height)
        let scaled = CGSize(width: size.width * fit, height: size.height * fit)
        let origin = CGPoint(x: (Self.side - scaled.width) / 2, y: (Self.side - scaled.height) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        var strokes = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            strokes = canvas.drawing.image(from: CGRect(origin: .zero, size: size), scale: fit)
        }
        return UIGraphicsImageRenderer(size: CGSize(width: Self.side, height: Self.side), format: format).image { _ in
            let area = kind.textArea
            let rect = CGRect(x: origin.x + area.minX * scaled.width, y: origin.y + area.minY * scaled.height,
                              width: area.width * scaled.width, height: area.height * scaled.height)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: Self.font, size: kind.fontSize * fit) ?? .systemFont(ofSize: kind.fontSize * fit),
                .foregroundColor: UIColor(Color(hex: ink.light)),
            ]
            (text as NSString).draw(with: rect, options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
            for item in decorations {
                guard let image = UIImage(named: item.asset) else { continue }
                let width = item.width * scaled.width
                let height = width * image.size.height / image.size.width
                let context = UIGraphicsGetCurrentContext()
                context?.saveGState()
                context?.translateBy(x: origin.x + item.x * scaled.width, y: origin.y + item.y * scaled.height)
                context?.rotate(by: item.angle)
                image.draw(in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
                context?.restoreGState()
            }
            strokes.draw(at: origin)
        }
    }
}

/// One image placed on the paper; positions and widths are fractions of the paper, the angle is in radians.
struct Decoration: Identifiable, Hashable {
    let id = UUID()
    let asset: String
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var angle: CGFloat = 0
}
