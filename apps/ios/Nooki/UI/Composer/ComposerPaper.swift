import PencilKit
import SwiftUI
import Design
import Wire

struct ComposerPaper: View {
    @Bindable var model: ComposerModel
    let size: CGSize
    @FocusState.Binding var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            PaperSheet(color: Color(hex: model.paper.hex), cornerRadius: 3, lift: .init(radius: 14, y: 8, opacity: 0.32))
            decoration
            textLayer
            decorationLayer
            ComposerInkLayer(model: model)
                .allowsHitTesting(model.drawing)
            curl
        }
        .frame(width: size.width, height: size.height)
        .postage(stamp: model.stamp?.art, seal: model.seal?.art, width: size.width)
        .animation(.snappy(duration: 0.2), value: model.stamp)
        .animation(.snappy(duration: 0.2), value: model.seal)
        .accessibilityElement(children: .contain)
    }

    private var area: CGRect {
        let a = model.kind.textArea
        return CGRect(x: a.minX * size.width, y: a.minY * size.height, width: a.width * size.width,
                      height: a.height * size.height)
    }

    @ViewBuilder private var decoration: some View {
        switch model.kind {
        case .sticky:
            EmptyView()
        case .letter:
            Canvas { context, canvas in
                let step = model.kind.fontSize * 1.55
                var y = area.minY + step
                while y < canvas.height - 10 {
                    context.stroke(Path { $0.move(to: CGPoint(x: 14, y: y)); $0.addLine(to: CGPoint(x: canvas.width - 14, y: y)) },
                                   with: .color(.black.opacity(0.1)), lineWidth: 1)
                    y += step
                }
                context.stroke(Path { $0.move(to: CGPoint(x: 0.12 * canvas.width, y: 0)); $0.addLine(to: CGPoint(x: 0.12 * canvas.width, y: canvas.height)) },
                               with: .color(.red.opacity(0.22)), lineWidth: 1)
            }
            .allowsHitTesting(false)
        case .polaroid:
            RoundedRectangle(cornerRadius: 2)
                .fill(.black.opacity(0.06))
                .frame(width: size.width * 0.86, height: size.height * 0.72)
                .position(x: size.width / 2, y: size.height * 0.04 + size.height * 0.36)
                .allowsHitTesting(false)
        }
    }

    private var textLayer: some View {
        TextField("", text: $model.text, prompt: Text("Write a little note…"), axis: .vertical)
            .font(.custom(ComposerModel.font, size: model.kind.fontSize))
            .foregroundStyle(Color(hex: model.ink.light))
            .lineLimit(model.kind == .polaroid ? 2 : 8, reservesSpace: false)
            .focused($focused)
            .frame(width: area.width, height: area.height, alignment: .topLeading)
            .position(x: area.midX, y: area.midY)
            .allowsHitTesting(!model.drawing)
            .onChange(of: model.text) { _, value in
                if value.count > NoteStore.maxLength { model.text = String(value.prefix(NoteStore.maxLength)) }
            }
            .accessibilityIdentifier("composerText")
    }

    private var decorationLayer: some View {
        ZStack {
            ForEach(model.decorations) { item in
                Image(item.asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: item.width * size.width)
                    .rotationEffect(.radians(item.angle))
                    .position(x: item.x * size.width, y: item.y * size.height)
            }
        }
        .allowsHitTesting(false)
    }

    private var curl: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            CurlCorner()
                .fill(LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.16)], startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .frame(width: 26, height: 26)
        }
        .allowsHitTesting(false)
    }

}

/// PencilKit over the paper with a clear background, so the paper and the text show through the strokes.
private struct ComposerInkLayer: UIViewRepresentable {
    let model: ComposerModel

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = model.canvas
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // PencilKit flips dark inks to light in dark mode; the paper is always light.
        canvas.overrideUserInterfaceStyle = .light
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {
        view.tool = PKInkingTool(.pen, color: UIColor(Color(hex: model.ink.light)), width: 6)
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let model: ComposerModel
        init(model: ComposerModel) { self.model = model }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let drawing = canvasView.drawing
            MainActor.assumeIsolated { model.inkChanged(drawing) }
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            guard AppSettings.haptics else { return }
            MainActor.assumeIsolated { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        }
    }
}

nonisolated struct CurlCorner: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

nonisolated struct Peak: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
