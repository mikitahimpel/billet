import MomentsInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import Design
import UsInterface

struct SheetSubtitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.ourioCaption)
            .foregroundStyle(Ink.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func addToolbarButton(_ label: String = "Add", action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: action) { Image(systemName: "plus") }
                    .accessibilityLabel(label)
            }
        }
    }
}

struct UsCheck: View {
    let done: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(done ? .clear : Ink.textSecondary, lineWidth: 1.5)
            if done {
                Circle().fill(Color.honey)
                Image(systemName: "checkmark")
                    .font(.ourioMicro)
                    .foregroundStyle(Ink.heroInk)
            }
        }
        .frame(width: 26, height: 26)
        .contentShape(.circle)
    }
}

struct UsField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        Field(placeholder, text: $text)
    }
}

/// A list's own "add" line: what is typed goes in as it is with Add or Return, and the field stays up for the next one.
struct AddItemField: View {
    let placeholder: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var onAdd: () -> Void

    private var canAdd: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: Space.s) {
            Field(placeholder, text: $text)
                .focused(focused)
                .submitLabel(.done)
                .onSubmit(onAdd)
            PillButton("Add", symbol: "plus", action: onAdd)
                .disabled(!canAdd)
                .accessibilityLabel(canAdd ? "Add \(text)" : "Add")
        }
    }
}

/// The first row of a list that adds through a sheet: says what tapping it adds.
struct AddRow: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Row(title, symbol: "plus") { EmptyView() }
        }
        .buttonStyle(RowButtonStyle())
    }
}

struct UsIcon: View {
    let glyph: UsGlyph
    var size: CGFloat = 44

    var body: some View {
        RowIcon(symbol: glyph.symbol, tint: glyph.tint.color, size: size)
    }
}

struct UsGlyphPicker: View {
    @Binding var selection: UsGlyph

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.m), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Space.m) {
            ForEach(UsGlyph.palette, id: \.self) { glyph in
                Button { selection = glyph } label: {
                    UsIcon(glyph: glyph, size: 34)
                        .opacity(selection == glyph ? 1 : 0.55)
                        .scaleEffect(selection == glyph ? 1.08 : 1)
                        .overlay(
                            Circle()
                                .stroke(Ink.text, lineWidth: selection == glyph ? 2 : 0)
                                .padding(-3)
                        )
                }
                .buttonStyle(PressScaleStyle())
                .animation(.snappy(duration: 0.2), value: selection)
            }
        }
        .padding(CardMetrics.padding)
        .cardSurface()
    }
}

extension EmptyState where Actions == EmptyView {
    init(icon: UsGlyph, title: String, text: String) {
        self.init(symbol: icon.symbol, title: title, text: text, tint: icon.tint.color)
    }
}

extension EmptyState {
    init(icon: UsGlyph, title: String, text: String, @ViewBuilder actions: () -> Actions) {
        self.init(symbol: icon.symbol, title: title, text: text, tint: icon.tint.color, actions: actions)
    }
}

extension UsTint {
    var color: Color { Color(hex: colors.top) }
}

struct PairToPlayButton: View {
    @Environment(ServerSession.self) private var session: ServerSession?
    @State private var pairing = false

    var body: some View {
        if let session, !session.isPaired, session.signIn.state == .signedIn {
            PrimaryButton("Pair with your partner", symbol: "heart.fill", fullWidth: false) { pairing = true }
                .padding(.top, Space.s)
                .sheet(isPresented: $pairing) {
                    PairingSheet(model: session.pairing) { session.pairingFinished() }
                }
        }
    }
}
