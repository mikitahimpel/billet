import SwiftUI

/// Shared look for the Us tab and its sheets, on the style guide's tokens (apps/ios/docs/style.md).
extension View {
    /// Sheet styled like the rest of the app, full height unless `detents` says otherwise.
    func usSheet(detents: Set<PresentationDetent> = [.large]) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationBackground(Ink.screen)
    }

    /// The card for rows and tiles.
    func usCard(radius: CGFloat = Radius.card) -> some View {
        background(Ink.surface, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Ink.separator, lineWidth: 0.5))
    }
}

/// Sheet header: big rounded title, optional trailing control.
struct UsSheetHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.nookiTitle)
                    .foregroundStyle(Ink.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.nookiCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
    }
}

extension UsSheetHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// The main action of a sheet, full width.
struct UsPrimaryButton: View {
    let title: String
    var symbol: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .nookiPrimary()
    }
}

/// Small round honey "+" used in headers.
struct UsAddButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.body.weight(.bold))
                .foregroundStyle(Ink.heroInk)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.honeyGradient))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add")
    }
}

/// Selectable capsule for filters and segmented choices.
struct UsChip: View {
    let title: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.nookiCallout)
                .foregroundStyle(selected ? Ink.heroInk : Ink.textSecondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(selected ? Color.honey : Ink.surfaceRaised, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Text field styled for the dark sheet.
struct UsField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Ink.textTertiary))
            .font(.nookiBody)
            .foregroundStyle(Ink.text)
            .padding(.horizontal, Space.l)
            .frame(minHeight: 50)
            .usCard(radius: Radius.control)
    }
}

/// The app's one row icon: an SF Symbol in its tint on a circle of the same tint.
struct UsIcon: View {
    let glyph: UsGlyph
    var size: CGFloat = 44

    var body: some View {
        let tint = Color(hex: glyph.tint.colors.top)
        Image(systemName: glyph.symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.2), in: .circle)
            .accessibilityHidden(true)
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
        .padding(Space.m)
        .usCard()
    }
}

/// Centered empty state with a big icon.
struct UsEmpty: View {
    let icon: UsGlyph
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            UsIcon(glyph: icon, size: 64)
                .padding(.bottom, 4)
            Text(title)
                .font(.nookiTitle)
                .foregroundStyle(Ink.text)
            Text(text)
                .font(.nookiCallout)
                .foregroundStyle(Ink.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}
