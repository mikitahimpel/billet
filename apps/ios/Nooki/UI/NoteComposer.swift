import FeatureShop
import MomentsInterface
import WidgetInterface
import WidgetUI
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
                        .onAppear { paperSize = size }
                        .onChange(of: size) { _, new in paperSize = new }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s)
            .safeAreaInset(edge: .bottom, spacing: 0) { tools }
        }
        .overlay { PurchaseMoment(state: state) }
        .haptic(.selection, trigger: model.ink)
        .haptic(.success, trigger: sending)
        .onAppear { focused = !model.drawing }
        .onChange(of: model.drawing) { _, drawing in focused = !drawing }
    }

    private func paper(fitting available: CGSize) -> CGSize {
        let room = CGSize(width: max(120, available.width), height: max(120, available.height))
        let width = min(room.width, room.height * model.kind.aspect)
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
        .overlay(alignment: .topTrailing) {
            LimitCounter(count: model.text.count, limit: NoteStore.maxLength, warnFrom: NoteStore.maxLength - 30)
                .padding(.horizontal, Space.gutter)
                .offset(y: -Space.l)
        }
        .animation(Motion.spring(0.2), value: model.hasInk)
    }

    private var toolToggle: some View {
        RoundButton(
            symbol: model.drawing ? "pencil.tip" : "character.cursor.ibeam",
            label: model.drawing ? "Type" : "Draw", style: model.drawing ? .honey : .quiet
        ) { model.drawing.toggle() }
        .accessibilityHint(model.drawing ? "Back to typing" : "Draw on the note with a pen")
        .accessibilityIdentifier("composerPen")
    }

    private var paperColours: some View {
        Menu {
            ForEach(Note.Paper.allCases, id: \.self) { option in
                Button(option.rawValue.capitalized) { model.paper = option }
            }
        } label: {
            Image(systemName: "paintpalette")
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
                .frame(width: Size.control, height: Size.control)
                .background { Circle().fill(Ink.well) }
        }
        .accessibilityLabel("Paper colour")
        .accessibilityValue(model.paper.rawValue.capitalized)
        .accessibilityIdentifier("composerPaperColour")
    }

    private var kindPicker: some View {
        RoundButton(symbol: model.kind.symbol, label: "Paper: \(model.kind.rawValue)") {
            let kinds = style.kinds
            let next = (kinds.firstIndex(of: model.kind) ?? 0) + 1
            withAnimation(Motion.spring()) { model.kind = kinds[next % kinds.count] }
        }
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
