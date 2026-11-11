import MomentsInterface
import OurioShared
import SwiftUI
import Design
import UsInterface

/// Sending pins the note and earns 5 coins.
struct NoteComposer: View {
    enum Mode: String, Identifiable {
        case write, draw
        var id: String { rawValue }
    }

    let state: HomeState
    let style: ComposerStyle

    @State private var model: ComposerModel
    @State private var flight = 0.0
    @State private var sending = false
    @State private var paperSize = CGSize(width: 280, height: 280)
    @State private var pats = 0
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(state: HomeState, mode: Mode, style: ComposerStyle = .current) {
        self.state = state
        self.style = style
        _model = State(initialValue: ComposerModel(kind: style.kinds[0], drawing: mode == .draw))
    }

    var body: some View {
        BilletSheet("New note", size: .large, scrolls: false, onConfirm: send,
                    canConfirm: !model.isEmpty && !sending) {
            GeometryReader { proxy in
                let size = paper(fitting: proxy.size)
                ZStack {
                    ComposerPaper(model: model, size: size, focused: $focused)
                        .sendFlight(style: style, color: Color(hex: model.paper.hex), progress: flight)
                        .overlay {
                            if style == .desk {
                                MochiOnDesk(activity: model.text.count + (model.hasInk ? 1 : 0) + pats, paper: size,
                                            swiping: .constant(sending))
                            }
                        }
                        .onAppear { paperSize = size }
                        .onChange(of: size) { _, new in paperSize = new }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xl)
            .safeAreaInset(edge: .bottom, spacing: 0) { tools }
        }
        .overlay { PurchaseMoment(state: state) }
        .haptic(.selection, trigger: model.ink)
        .haptic(.success, trigger: sending)
        .onAppear { focused = !model.drawing }
        .onChange(of: model.drawing) { _, drawing in focused = !drawing }
    }

    private func paper(fitting available: CGSize) -> CGSize {
        let room = CGSize(width: max(120, available.width), height: max(120, available.height - Space.xl))
        let width = min(room.width, room.height * model.kind.aspect, 340)
        return CGSize(width: width, height: width / model.kind.aspect)
    }

    private var tools: some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                toolToggle
                paperColours
                PostagePicker(stamp: $model.stamp, seal: $model.seal)
                Spacer(minLength: 0)
                if style != .sticky { kindPicker }
                if model.hasInk {
                    GlassIconButton(symbol: "arrow.uturn.backward", label: "Undo") { model.undo() }
                    GlassIconButton(symbol: "trash", label: "Clear") { model.clear() }
                }
            }
            .padding(.horizontal, Space.gutter)
            PenHolder(style: style, state: state, selection: $model.ink) { dismiss() }
        }
        .padding(.vertical, Space.s)
        .animation(.snappy(duration: 0.2), value: model.hasInk)
    }

    private var toolToggle: some View {
        Button { model.drawing.toggle() } label: {
            Image(systemName: model.drawing ? "pencil.tip" : "character.cursor.ibeam")
                .font(.ourioCallout.weight(.semibold))
                .foregroundStyle(model.drawing ? Ink.heroInk : Ink.text)
                .frame(width: Size.control, height: Size.control)
                .background(model.drawing ? Color.honey : Ink.surface, in: .circle)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(model.drawing ? "Pen on" : "Pen off")
        .accessibilityHint("Switches between drawing and typing")
        .accessibilityIdentifier("composerPen")
    }

    private var paperColours: some View {
        Menu {
            ForEach(Note.Paper.allCases, id: \.self) { option in
                Button(option.rawValue.capitalized) { model.paper = option }
            }
        } label: {
            Circle()
                .fill(Color(hex: model.paper.hex))
                .overlay(Circle().strokeBorder(Ink.text.opacity(0.3), lineWidth: 1))
                .frame(width: 28, height: 28)
                .frame(width: Size.control, height: Size.control)
        }
        .accessibilityLabel("Paper colour")
        .accessibilityIdentifier("composerPaperColour")
    }

    private var kindPicker: some View {
        Button {
            let kinds = style.kinds
            let next = (kinds.firstIndex(of: model.kind) ?? 0) + 1
            withAnimation(.snappy) { model.kind = kinds[next % kinds.count] }
            pats += 1
        } label: {
            Image(systemName: model.kind.symbol)
                .font(.ourioCallout.weight(.semibold))
                .foregroundStyle(Ink.text)
                .frame(width: Size.control, height: Size.control)
                .background(Ink.surface, in: .circle)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Paper: \(model.kind.rawValue)")
        .accessibilityIdentifier("composerPaperKind")
    }

    private func send() {
        guard !sending, model.save(into: state.journal, size: paperSize) else { return }
        focused = false
        sending = true
        guard !reduceMotion else { return dismiss() }
        SendFlight.playSound()
        withAnimation(.easeIn(duration: SendFlight.duration)) { flight = 1 }
        Task {
            try? await Task.sleep(for: .seconds(SendFlight.duration))
            dismiss()
        }
    }
}
