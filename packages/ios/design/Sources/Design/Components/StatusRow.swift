import SwiftUI

/// A state read at a glance, in a `GroupedSection(inset: StatusRow.inset)`: an icon, a name over
/// the state in a word or two, and at the trailing edge either the action a tap on the row runs or
/// a short note when nothing can be done. `raised` is for a state that wants something now: its
/// icon turns solid and its action takes the tint, so it reads first while the rest stay quiet.
public struct StatusRow: View {
  public enum Emphasis: Hashable, Sendable {
    case quiet
    case raised
  }

  /// Where the hairlines between rows start: under the words.
  public static let inset: CGFloat = Space.l + mark + Space.m
  static let mark: CGFloat = 34

  let title: String
  let state: String
  let symbol: String
  let tint: Color
  let emphasis: Emphasis
  let trail: String
  let value: String?
  let hint: String?
  let perform: (() -> Void)?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// - Parameters:
  ///   - value: Read by VoiceOver in place of `state`, for detail the screen leaves out.
  ///   - action: The words on the trailing pill.
  ///   - hint: Read by VoiceOver; `action` when nil.
  public init(
    _ title: String, state: String, symbol: String, tint: Color = .honey,
    emphasis: Emphasis = .quiet, value: String? = nil, action: String, hint: String? = nil,
    perform: @escaping () -> Void
  ) {
    self.title = title
    self.state = state
    self.symbol = symbol
    self.tint = tint
    self.emphasis = emphasis
    self.trail = action
    self.value = value
    self.hint = hint
    self.perform = perform
  }

  /// A row nothing can be done about: `note` says why, at the trailing edge.
  public init(
    _ title: String, state: String, symbol: String, tint: Color = .honey,
    emphasis: Emphasis = .quiet, value: String? = nil, note: String
  ) {
    self.title = title
    self.state = state
    self.symbol = symbol
    self.tint = tint
    self.emphasis = emphasis
    self.trail = note
    self.value = value
    self.hint = nil
    self.perform = nil
  }

  public var body: some View {
    if let perform {
      Button(action: perform) { content }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(value ?? state)
        .accessibilityHint(hint ?? trail)
    } else {
      content
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value ?? state), \(trail)")
    }
  }

  /// At accessibility sizes the icon and the action share the first line and the words take the
  /// row's whole width under them; a note goes under the words.
  private var content: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: Space.s) {
          HStack(spacing: Space.m) {
            icon
            Spacer(minLength: Space.s)
            if perform != nil { trailing }
          }
          words
          if perform == nil { trailing }
        }
      } else {
        HStack(spacing: Space.m) {
          icon
          words.layoutPriority(1)
          Spacer(minLength: Space.s)
          trailing
        }
      }
    }
    .padding(.horizontal, Space.l)
    .padding(.vertical, Space.s)
    .frame(maxWidth: .infinity, minHeight: Size.row, alignment: .leading)
    .contentShape(.rect)
    .animation(Motion.fade(), value: emphasis)
  }

  private var icon: some View {
    RowIcon(symbol: symbol, tint: tint, size: Self.mark, style: emphasis == .raised ? .clay : .well)
  }

  private var words: some View {
    VStack(alignment: .leading, spacing: Space.xxs) {
      Text(title)
        .font(.ourioCaption)
        .foregroundStyle(Ink.textSecondary)
      Text(state)
        .font(.ourioHeadline)
        .foregroundStyle(Ink.text)
        .contentTransition(.opacity)
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder private var trailing: some View {
    if perform == nil {
      Text(trail)
        .font(.ourioCaption)
        .foregroundStyle(Ink.textSecondary)
        .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
        .fixedSize(horizontal: false, vertical: true)
    } else {
      switch emphasis {
      case .quiet:
        pill
          .foregroundStyle(Ink.accentText)
          .background(Ink.surfaceRaised, in: .capsule)
          .overlay { Capsule().strokeBorder(Ink.accentText.opacity(0.45), lineWidth: 1) }
      case .raised:
        pill
          .foregroundStyle(Ink.heroInk)
          .background(tint, in: .capsule)
      }
    }
  }

  /// Drawn like `PillButtonStyle`, but only a label: the whole row is the button.
  private var pill: some View {
    Text(trail)
      .font(.ourioCallout.weight(.semibold))
      .lineLimit(1)
      .fixedSize()
      .padding(.horizontal, Space.m)
      .frame(minHeight: Size.pill)
  }
}

#Preview("Status rows") {
  BothSchemes {
    GroupedSection(inset: StatusRow.inset) {
      StatusRow(
        "Water", state: "Thirsty", symbol: "drop.fill", emphasis: .raised, action: "Water"
      ) {}
      StatusRow("Light", state: "Plenty", symbol: "sun.max.fill", note: "Moves on its own")
      StatusRow(
        "Love", state: "Wants a hug", symbol: "heart.fill", tint: .blushPink, emphasis: .raised,
        action: "Hug"
      ) {}
      StatusRow("Food", state: "Well fed", symbol: "fork.knife", action: "Feed") {}
    }
    .padding(Space.gutter)
  }
}
