import SwiftUI

/// A centred empty state sized to its content: an icon, a title and a line under it. It never fills the space
/// around it.
public struct EmptyState<Actions: View>: View {
  let symbol: String
  let title: String
  let text: String?
  let tint: Color
  let actions: Actions

  public init(
    symbol: String, title: String, text: String? = nil, tint: Color = .honey,
    @ViewBuilder actions: () -> Actions
  ) {
    self.symbol = symbol
    self.title = title
    self.text = text
    self.tint = tint
    self.actions = actions()
  }

  public var body: some View {
    VStack(spacing: Space.s + 2) {
      RowIcon(symbol: symbol, tint: tint, size: 64)
        .padding(.bottom, Space.xs)
      Text(title)
        .font(.nookiTitle)
        .foregroundStyle(Ink.text)
        .multilineTextAlignment(.center)
      if let text {
        Text(text)
          .font(.nookiCallout)
          .foregroundStyle(Ink.textSecondary)
          .multilineTextAlignment(.center)
      }
      actions
    }
    .padding(.horizontal, Space.xl)
    .padding(.vertical, Space.xl)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .contain)
  }
}

extension EmptyState where Actions == EmptyView {
  public init(symbol: String, title: String, text: String? = nil, tint: Color = .honey) {
    self.init(symbol: symbol, title: title, text: text, tint: tint) { EmptyView() }
  }
}

/// The title of a block on a screen: an optional icon in its tint, the title, and a quiet line on the right.
public struct SectionHeader<Trailing: View>: View {
  let title: String
  let symbol: String?
  let tint: Color
  let trailing: Trailing

  public init(
    _ title: String, symbol: String? = nil, tint: Color = .honey,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.symbol = symbol
    self.tint = tint
    self.trailing = trailing()
  }

  public var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
      if let symbol {
        Image(systemName: symbol)
          .font(.nookiCallout.weight(.semibold))
          .foregroundStyle(tint)
          .accessibilityHidden(true)
      }
      Text(title)
        .font(.nookiHeadline)
        .foregroundStyle(Ink.text)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: Space.s)
      trailing
        .font(.nookiCaption)
        .foregroundStyle(Ink.textSecondary)
    }
  }
}

extension SectionHeader where Trailing == EmptyView {
  public init(_ title: String, symbol: String? = nil, tint: Color = .honey) {
    self.init(title, symbol: symbol, tint: tint) { EmptyView() }
  }
}

/// A small label: a rarity, a discount, a count. Its text is always `Ink.text` or `Ink.heroInk`, so it reads on
/// any tint.
public struct Chip: View {
  public enum Style: Sendable {
    /// Neutral, on a raised surface.
    case quiet
    /// A tinted wash with `Ink.text` on it.
    case tinted(Color)
    /// Honey with `Ink.heroInk` on it, for the one thing worth noticing.
    case honey
  }

  let title: String
  let symbol: String?
  let style: Style

  public init(_ title: String, symbol: String? = nil, style: Style = .quiet) {
    self.title = title
    self.symbol = symbol
    self.style = style
  }

  public var body: some View {
    HStack(spacing: Space.xs) {
      if let symbol { Image(systemName: symbol).foregroundStyle(accent) }
      Text(title)
    }
    .font(.nookiMicro)
    .foregroundStyle(style.isHoney ? Ink.heroInk : Ink.text)
    .padding(.horizontal, Space.s)
    .frame(minHeight: 22)
    .background(fill, in: .capsule)
    .fixedSize()
  }

  private var accent: Color {
    switch style {
    case .quiet: Ink.textSecondary
    case .tinted(let tint): tint
    case .honey: Ink.heroInk
    }
  }

  private var fill: Color {
    switch style {
    case .quiet: Ink.surfaceRaised
    case .tinted(let tint): tint.opacity(0.28)
    case .honey: .honey
    }
  }
}

extension Chip.Style {
  fileprivate var isHoney: Bool {
    if case .honey = self { true } else { false }
  }
}

/// A selectable capsule for filters and categories.
public struct FilterChip: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
    self.title = title
    self.isSelected = isSelected
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      Text(title)
        .font(.nookiCallout)
        .foregroundStyle(isSelected ? Ink.heroInk : Ink.textSecondary)
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .background(isSelected ? Color.honey : Ink.surfaceRaised, in: .capsule)
        .frame(minHeight: Size.control)
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

#Preview("Labels") {
  VStack(spacing: Space.l) {
    EmptyState(symbol: "tray", title: "All quiet", text: "Notes and gifts show up here.")
    SectionHeader("Daily deals", symbol: "tag.fill", tint: .honeyDeep) { Text("New at midnight") }
    HStack {
      Chip("Rare", style: .tinted(.teal))
      Chip("-20%", style: .honey)
      Chip("Owned", symbol: "checkmark")
      FilterChip("Today", isSelected: true) {}
      FilterChip("Cats", isSelected: false) {}
    }
  }
  .padding(Space.gutter)
  .background(Ink.screen)
}
