#if DEBUG || LABS_YES
import Design
import FoldInterface
import SwiftUI
import WidgetUI
import Wire

/// A window onto the folded sheet: the part from `top` down for `height`, both as fractions of the sheet's width,
/// with the lines that lie in it. A finger is reported as a place on the whole sheet, and nil when it lifts.
struct FoldPaper: View {
    let strokes: [Stroke]
    let top: Double
    let height: Double
    /// Shaded from here down to the fold: the strip the next drawer will see. Nil when there is none to show.
    var strip: ClosedRange<Double>?
    /// A line across the sheet where it is folded.
    var fold: Double?
    var touch: ((Point?) -> Void)?

    @State private var width: CGFloat = 0

    var body: some View {
        ZStack {
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Ink.well))
                if let strip {
                    let band = CGRect(x: 0, y: (strip.lowerBound - top) * size.width, width: size.width,
                                      height: (strip.upperBound - strip.lowerBound) * size.width)
                    context.fill(Path(band), with: .color(Color.honey.opacity(0.16)))
                }
                if let fold {
                    // Dashes as small filled bars, so the fold reads as a crease and not as a drawn line.
                    var dashes = Path()
                    var x: CGFloat = 0
                    while x < size.width {
                        dashes.addRect(CGRect(x: x, y: (fold - top) * size.width, width: Space.s, height: 1))
                        x += Space.s + Space.xs
                    }
                    context.fill(dashes, with: .color(Ink.textTertiary))
                }
            }
            InkLayer(strokes: FoldSheet.moved(strokes, by: -top))
        }
        .aspectRatio(1 / height, contentMode: .fit)
        .corners(.inner)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    guard width > 0 else { return }
                    touch?(Point(x: value.location.x / width, y: top + value.location.y / width))
                }
                .onEnded { _ in touch?(nil) }
        )
        .accessibilityElement()
        .accessibilityLabel("The sheet")
    }
}
#endif
