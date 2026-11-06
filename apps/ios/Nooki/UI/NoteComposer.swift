import PencilKit
import SwiftUI
import Design

/// Sheet for writing a line or doodling on a piece of paper; saving pins it and earns 5 coins.
struct NoteComposer: View {
    enum Mode: String, Identifiable {
        case write, draw
        var id: String { rawValue }
    }

    let state: HomeState
    @State var mode: Mode

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var paper: Note.Paper = .butter
    @State private var ink = PaletteInk.free
    @State private var drawing = PKDrawing()
    @State private var canvas = PKCanvasView()
    @FocusState private var focused: Bool

    private static let side: CGFloat = 280

    private var isEmpty: Bool {
        switch mode {
        case .write: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .draw: drawing.strokes.isEmpty
        }
    }

    var body: some View {
        BilletSheet("New note", size: .large) {
            VStack(spacing: Space.l + 4) {
                Picker("Style", selection: $mode) {
                    Text("Write").tag(Mode.write)
                    Text("Draw").tag(Mode.draw)
                }
                .pickerStyle(.segmented)

                paperView

                inkRow

                paperRow

                PrimaryButton("Pin it · +5", action: save)
                    .monospacedDigit()
                    .disabled(isEmpty)
            }
            .frame(maxWidth: .infinity)
        }
        // Over the sheet: an ink bought here plays its moment and Undo where it was tapped.
        .overlay { PurchaseMoment(state: state) }
        .onAppear { focused = mode == .write }
        .onChange(of: mode) { _, new in focused = new == .write }
    }

    private var paperView: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: paper.hex)
            switch mode {
            case .write:
                VStack(spacing: 0) {
                    TextField("", text: $text, prompt: Text("Write a little note…"), axis: .vertical)
                        .font(.custom("Noteworthy-Bold", size: 22))
                        .foregroundStyle(Color(hex: ink.light))
                        .lineLimit(6)
                        .focused($focused)
                        .onChange(of: text) { _, value in
                            if value.count > NoteStore.maxLength {
                                text = String(value.prefix(NoteStore.maxLength))
                            }
                        }
                    Spacer(minLength: 0)
                }
                .padding(20)
            case .draw:
                DoodleCanvas(canvas: canvas, ink: Color(hex: ink.light)) { drawing = $0 }
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(.rect(cornerRadius: 4))
        .rotationEffect(.degrees(-1.5))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .animation(.snappy(duration: 0.2), value: mode)
    }

    private var inkRow: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal) {
                InkPalette(state: state, selection: $ink)
            }
            .scrollIndicators(.hidden)
            if mode == .draw { drawButtons }
        }
    }

    private var drawButtons: some View {
        HStack(spacing: Space.s) {
            GlassIconButton(symbol: "arrow.uturn.backward", label: "Undo") { canvas.undoManager?.undo() }
            GlassIconButton(symbol: "trash", label: "Clear") { clear() }
        }
    }

    private var paperRow: some View {
        HStack(spacing: 12) {
            ForEach(Note.Paper.allCases, id: \.self) { option in
                Button { paper = option } label: {
                    dot(Color(hex: option.hex), selected: paper == option)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.rawValue.capitalized)
            }
        }
    }

    private func dot(_ color: Color, selected: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 28, height: 28)
            .overlay(Circle().stroke(Ink.text, lineWidth: 2).opacity(selected ? 1 : 0))
    }

    private func clear() {
        canvas.drawing = PKDrawing()
        drawing = PKDrawing()
    }

    private func save() {
        switch mode {
        case .write:
            guard state.journal.addNote(text: text, paper: paper, ink: ink.light) else { return }
        case .draw:
            let frame = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
            var image = UIImage()
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                image = canvas.drawing.image(from: frame, scale: 2)
            }
            guard state.journal.addNote(doodle: image, paper: paper) else { return }
        }
        dismiss()
    }
}

/// PencilKit canvas with a transparent background, so the paper color shows through the strokes.
private struct DoodleCanvas: UIViewRepresentable {
    let canvas: PKCanvasView
    let ink: Color
    let onChange: (PKDrawing) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // PencilKit flips dark inks to light in dark mode; the paper is always light.
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: UIColor(ink), width: 6)
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {
        view.tool = PKInkingTool(.pen, color: UIColor(ink), width: 6)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let onChange: (PKDrawing) -> Void

        init(onChange: @escaping (PKDrawing) -> Void) {
            self.onChange = onChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onChange(canvasView.drawing)
        }
    }
}
