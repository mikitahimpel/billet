import SwiftUI

/// A settings-like screen in the app's style instead of the system's grouped list: `Ink.screen` behind clay-card
/// sections that scroll as one page.
struct NookiForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                content
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.l)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Ink.screen.ignoresSafeArea())
        .tint(.honey)
    }
}

/// A group of rows on one clay card, hairlines between them, with an optional caption above and a footer below.
struct NookiSection<Content: View>: View {
    var header: String?
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let header {
                Text(header)
                    .font(.nookiCaption.weight(.semibold))
                    .foregroundStyle(Ink.textSecondary)
                    .padding(.horizontal, Space.l)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle().fill(Ink.separator).frame(height: 0.5).padding(.leading, 62)
                        }
                        row
                    }
                }
            }
            .nookiCard()
            if let footer {
                Text(footer)
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
                    .padding(.horizontal, Space.l)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A row's face: its icon in a tinted circle, the title with an optional line under it, and whatever goes on the
/// right.
struct NookiRowLabel<Trailing: View>: View {
    let title: String
    var detail: String?
    let symbol: String
    let tint: UsTint
    var destructive = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            UsIcon(glyph: .init(symbol: symbol, tint: tint), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.nookiBody)
                    .foregroundStyle(destructive ? ShopInk.coral : Ink.text)
                if let detail {
                    Text(detail)
                        .font(.nookiCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
            }
            Spacer(minLength: Space.s)
            trailing
        }
        .padding(.horizontal, Space.m + 2)
        .padding(.vertical, Space.s + 2)
        .frame(minHeight: 54)
        .contentShape(.rect)
    }
}

extension NookiRowLabel where Trailing == EmptyView {
    init(title: String, detail: String? = nil, symbol: String, tint: UsTint, destructive: Bool = false) {
        self.init(title: title, detail: detail, symbol: symbol, tint: tint, destructive: destructive) { EmptyView() }
    }
}

/// The chevron of a row that opens another screen.
struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.nookiCaption.weight(.semibold))
            .foregroundStyle(Ink.textTertiary)
            .accessibilityHidden(true)
    }
}

/// A row that switches something on and off, with the honey switch.
struct NookiToggleRow: View {
    let title: String
    var detail: String?
    let symbol: String
    let tint: UsTint
    @Binding var isOn: Bool

    var body: some View {
        NookiRowLabel(title: title, detail: detail, symbol: symbol, tint: tint) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(.honey)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A row that picks one of a few values from a menu, the current one shown on the right in honey.
struct NookiPickerRow<Value: Hashable, Options: View>: View {
    let title: String
    let symbol: String
    let tint: UsTint
    @Binding var selection: Value
    @ViewBuilder let options: Options

    var body: some View {
        NookiRowLabel(title: title, symbol: symbol, tint: tint) {
            Picker(title, selection: $selection) { options }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(Ink.accentText)
        }
    }
}
