import SwiftUI

/// Sized to its content; it never fills the space around it.
public struct EmptyState<Actions: View>: View {
  let symbol: String
  let title: String
  let text: String?
  let tint: Color?
  let actions: Actions

  public init(
    symbol: String, title: String, text: String? = nil, tint: Color? = nil,
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
        .font(.ourioTitle)
        .foregroundStyle(Ink.text)
        .multilineTextAlignment(.center)
      if let text {
        Text(text)
          .font(.ourioCallout)
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
  public init(symbol: String, title: String, text: String? = nil, tint: Color? = nil) {
    self.init(symbol: symbol, title: title, text: text, tint: tint) { EmptyView() }
  }
}

public struct SectionHeader<Trailing: View>: View {
  let title: String
  let symbol: String?
  let tint: Color?
  let trailing: Trailing
  @Environment(\.dynamicTypeSize) private var typeSize

  public init(
    _ title: String, symbol: String? = nil, tint: Color? = nil,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.symbol = symbol
    self.tint = tint
    self.trailing = trailing()
  }

  public var body: some View {
    if typeSize.isAccessibilitySize {
      // A word never breaks: the trailing detail takes its own line under the title.
      VStack(alignment: .leading, spacing: Space.xs) {
        heading
        trailing
          .font(.ourioCaption)
          .foregroundStyle(Ink.textSecondary)
      }
    } else {
      HStack(alignment: .firstTextBaseline, spacing: Space.s) {
        heading
        Spacer(minLength: Space.s)
        trailing
          .font(.ourioCaption)
          .foregroundStyle(Ink.textSecondary)
      }
    }
  }

  private var heading: some View {
    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
      if let symbol {
        Image(systemName: symbol)
          .font(.ourioCallout.weight(.semibold))
          .foregroundStyle(tint ?? Ink.accentText)
          .accessibilityHidden(true)
      }
      Text(title)
        .font(.ourioHeadline)
        .foregroundStyle(Ink.text)
        .accessibilityAddTraits(.isHeader)
    }
  }
}

extension SectionHeader where Trailing == EmptyView {
  public init(_ title: String, symbol: String? = nil, tint: Color? = nil) {
    self.init(title, symbol: symbol, tint: tint) { EmptyView() }
  }
}

/// Its text is always `Ink.text` or `Ink.heroInk`, so it reads on any tint.
public struct Chip: View {
  public enum Style: Sendable {
    case quiet
    case tinted(Color)
    /// For the one thing worth noticing.
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
    .font(.ourioMicro)
    .foregroundStyle(style.isHoney ? Ink.heroInk : Ink.text)
    .padding(.horizontal, Space.s)
    .frame(minHeight: 22)
    .background(fill, in: .capsule)
    .fixedSize()
    // A tag stays a tag: past this it would crowd out the words it labels. VoiceOver reads it whole.
    .dynamicTypeSize(...Chip.largestType)
  }

  static let largestType = DynamicTypeSize.accessibility1

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
        .font(.ourioCallout)
        .foregroundStyle(isSelected ? Ink.heroInk : Ink.textSecondary)
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .background(isSelected ? Color.honey : Ink.surfaceRaised, in: .capsule)
        .frame(minHeight: Size.control)
        .contentShape(.rect)
    }
    .buttonStyle(PressScaleStyle())
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
