#if DEBUG || LABS_YES
import Design
import PackInterface
import SwiftUI

/// The open suitcase from above: a grid of squares with what lies in it. A tap is reported as a square.
struct PackBoardCanvas: View {
    let suitcase: PackCase
    let tap: (PackCell) -> Void

    @State private var width: CGFloat = 0

    var body: some View {
        let level = suitcase.level
        Canvas { context, size in
            let cell = size.width / CGFloat(level.width)
            func rect(_ at: PackCell) -> CGRect {
                CGRect(x: CGFloat(at.x) * cell, y: CGFloat(at.y) * cell, width: cell, height: cell)
            }
            let corner = CGSize(width: Space.s, height: Space.s)
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerSize: corner),
                         with: .color(Ink.well))
            for y in 0..<level.height {
                for x in 0..<level.width {
                    let square = rect(PackCell(x: x, y: y)).insetBy(dx: Space.xxs, dy: Space.xxs)
                    context.stroke(Path(roundedRect: square, cornerSize: CGSize(width: Space.xs, height: Space.xs)),
                                   with: .color(Ink.separator), lineWidth: 1)
                }
            }
            for piece in level.pieces {
                guard let placement = suitcase.placed[piece.id] else { continue }
                let cells = suitcase.cells(of: piece, placement)
                var path = Path()
                for at in cells { path.addRect(rect(at).insetBy(dx: 1, dy: 1)) }
                context.fill(path, with: .color(PackLook.color(piece)))
                if let first = cells.min() {
                    context.draw(Text(PackLook.short(piece)).font(.ourioMicro).foregroundStyle(Ink.text),
                                 in: rect(first).insetBy(dx: Space.xxs, dy: Space.xxs))
                }
            }
        }
        .aspectRatio(CGFloat(level.width) / CGFloat(level.height), contentMode: .fit)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(.rect)
        .gesture(
            SpatialTapGesture().onEnded { value in
                guard width > 0 else { return }
                let cell = width / CGFloat(level.width)
                let at = PackCell(x: Int(value.location.x / cell), y: Int(value.location.y / cell))
                guard (0..<level.width).contains(at.x), (0..<level.height).contains(at.y) else { return }
                tap(at)
            }
        )
        .accessibilityElement()
        .accessibilityLabel("The suitcase")
        .accessibilityValue("\(suitcase.placed.count) of \(level.pieces.count) in")
    }
}

/// One piece's outline, small, turned as it is held.
struct PackShapeGlyph: View {
    let shape: PackShape
    let color: Color

    var body: some View {
        Canvas { context, size in
            let cell = min(size.width, size.height) / 5
            let left = (size.width - CGFloat(shape.width) * cell) / 2
            let top = (size.height - CGFloat(shape.height) * cell) / 2
            var path = Path()
            for at in shape.cells {
                path.addRect(CGRect(x: left + CGFloat(at.x) * cell, y: top + CGFloat(at.y) * cell,
                                    width: cell, height: cell).insetBy(dx: 1, dy: 1))
            }
            context.fill(path, with: .color(color))
        }
        .frame(width: Size.control, height: Size.control)
        .accessibilityHidden(true)
    }
}

enum PackLook {
    static func color(_ piece: PackPiece) -> Color {
        switch piece.content {
        case .thing(_, .first): Color.honey
        case .thing(_, .second): Color.lilac
        case .cat: Color.blushPink
        }
    }

    static func title(_ piece: PackPiece, cat: String) -> String {
        switch piece.content {
        case .thing(let thing, _): thing.title
        case .cat: cat
        }
    }

    static func short(_ piece: PackPiece) -> String {
        switch piece.content {
        case .thing(let thing, _): thing.title
        case .cat: "Cat"
        }
    }
}
#endif
