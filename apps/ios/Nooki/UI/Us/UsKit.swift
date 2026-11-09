import SwiftUI
import Design

/// A line under a sheet's title, for what the title alone doesn't say.
struct SheetSubtitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.nookiCaption)
            .foregroundStyle(Ink.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// The "+" of a sheet's header, in the navigation bar's leading glass.
    func addToolbarButton(_ label: String = "Add", action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: action) { Image(systemName: "plus") }
                    .accessibilityLabel(label)
            }
        }
    }
}

/// The round tick of a list row: an empty ring, honey with a checkmark once done.
struct UsCheck: View {
    let done: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(done ? .clear : Ink.textSecondary, lineWidth: 1.5)
            if done {
                Circle().fill(Color.honey)
                Image(systemName: "checkmark")
                    .font(.nookiMicro)
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

/// The app's one row icon: an SF Symbol in its tint on a circle of the same tint.
struct UsIcon: View {
    let glyph: UsGlyph
    var size: CGFloat = 44

    var body: some View {
        RowIcon(symbol: glyph.symbol, tint: glyph.tint.color, size: size)
    }
}

/// Grid of palette icons to pick one from.
struct UsGlyphPicker: View {
    @Binding var selection: UsGlyph

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
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
                .buttonStyle(.plain)
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

extension UsTint {
    var color: Color { Color(hex: colors.top) }
}
