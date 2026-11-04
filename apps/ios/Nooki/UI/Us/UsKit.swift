import SwiftUI

/// Shared look for the Us tab and its sheets: warm dark sheet, cream cards, honey primary buttons.
extension View {
    /// Sheet styled like the rest of the app, full height unless `detents` says otherwise.
    func usSheet(detents: Set<PresentationDetent> = [.large]) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationBackground(Ink.sheet)
            .presentationCornerRadius(36)
    }

    /// Rounded translucent card used for rows and tiles.
    func usCard(radius: CGFloat = 20) -> some View {
        background(Ink.card, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Ink.hairline, lineWidth: 0.5))
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
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Ink.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.secondary)
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

/// Honey capsule for the main action of a screen.
struct UsPrimaryButton: View {
    let title: String
    var symbol: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Capsule().fill(.honeyGradient))
            .shadow(color: Color.honeyDeep.opacity(0.4), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}

/// Small round honey "+" used in headers.
struct UsAddButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.honeyGradient))
                .shadow(color: Color.honeyDeep.opacity(0.4), radius: 8, y: 3)
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
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? Ink.primary : Ink.secondary)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(selected ? Color.honey.opacity(0.32) : .white.opacity(0.1), in: .capsule)
                .overlay(Capsule().stroke(selected ? .clear : Ink.hairline, lineWidth: 0.5))
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
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Ink.secondary.opacity(0.7)))
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Ink.primary)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .usCard(radius: 16)
    }
}

/// App-style icon: a white SF Symbol on a glossy gradient tile, like the honey "+" buttons.
struct UsIcon: View {
    let glyph: UsGlyph
    var size: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
        Image(systemName: glyph.symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
            .frame(width: size, height: size)
            .background {
                shape.fill(LinearGradient(colors: [Color(hex: glyph.tint.colors.top), Color(hex: glyph.tint.colors.bottom)],
                                          startPoint: .top, endPoint: .bottom))
                // Soft top highlight gives the clay/glossy feel of the room's objects.
                shape.fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                    .padding(1.5)
            }
            .overlay(shape.stroke(.white.opacity(0.3), lineWidth: 0.75))
            .shadow(color: Color(hex: glyph.tint.colors.bottom).opacity(0.35), radius: size * 0.12, y: size * 0.06)
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
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(.white, lineWidth: selection == glyph ? 2 : 0)
                                .padding(-3)
                        )
                }
                .buttonStyle(.plain)
                .animation(.snappy(duration: 0.2), value: selection)
            }
        }
        .padding(12)
        .usCard(radius: 18)
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
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.primary)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}
