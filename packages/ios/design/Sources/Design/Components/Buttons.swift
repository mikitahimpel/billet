import SwiftUI

/// `Ink.heroInk` text, since white on honey is too faint to read.
public struct PrimaryButtonStyle: ButtonStyle {
  var fullWidth: Bool
  @Environment(\.isEnabled) private var isEnabled

  public init(fullWidth: Bool = true) { self.fullWidth = fullWidth }

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.ourioHeadline)
      .foregroundStyle(isEnabled ? Ink.heroInk : Ink.disabledText)
      .padding(.horizontal, Space.xl)
      .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Size.button)
      .background(isEnabled ? Ink.accentFace : AnyShapeStyle(Ink.disabledFill), in: .capsule)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(Motion.spring(0.2), value: configuration.isPressed)
  }
}

public struct SecondaryButtonStyle: ButtonStyle {
  var fullWidth: Bool
  @Environment(\.isEnabled) private var isEnabled

  public init(fullWidth: Bool = true) { self.fullWidth = fullWidth }

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.ourioHeadline)
      .foregroundStyle(isEnabled ? Ink.accentText : Ink.disabledText)
      .padding(.horizontal, Space.xl)
      .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Size.button)
      .background(isEnabled ? Ink.surfaceRaised : Ink.disabledFill, in: .capsule)
      .overlay {
        if isEnabled { Capsule().strokeBorder(Ink.accentText.opacity(0.45), lineWidth: 1) }
      }
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(Motion.spring(0.2), value: configuration.isPressed)
  }
}

public struct PrimaryButton: View {
  let title: String
  let symbol: String?
  let fullWidth: Bool
  let action: () -> Void

  public init(
    _ title: String, symbol: String? = nil, fullWidth: Bool = true, action: @escaping () -> Void
  ) {
    self.title = title
    self.symbol = symbol
    self.fullWidth = fullWidth
    self.action = action
  }

  public var body: some View {
    Button(action: action) { ButtonLabel(title: title, symbol: symbol) }
      .buttonStyle(PrimaryButtonStyle(fullWidth: fullWidth))
  }
}

public struct SecondaryButton: View {
  let title: String
  let symbol: String?
  let fullWidth: Bool
  let action: () -> Void

  public init(
    _ title: String, symbol: String? = nil, fullWidth: Bool = true, action: @escaping () -> Void
  ) {
    self.title = title
    self.symbol = symbol
    self.fullWidth = fullWidth
    self.action = action
  }

  public var body: some View {
    Button(action: action) { ButtonLabel(title: title, symbol: symbol) }
      .buttonStyle(SecondaryButtonStyle(fullWidth: fullWidth))
  }
}

private struct ButtonLabel: View {
  let title: String
  let symbol: String?

  var body: some View {
    HStack(spacing: Space.s) {
      if let symbol { Image(systemName: symbol) }
      Text(title)
    }
  }
}

public struct GlassIconButton<Content: View>: View {
  public enum Badge: Equatable, Sendable {
    case none
    case dot
    case count(Int)
  }

  let label: String
  let badge: Badge
  let action: () -> Void
  let content: Content

  public init(
    label: String, badge: Badge = .none, action: @escaping () -> Void,
    @ViewBuilder content: () -> Content
  ) {
    self.label = label
    self.badge = badge
    self.action = action
    self.content = content()
  }

  public var body: some View {
    Button(action: action) {
      content
        .frame(width: Size.control, height: Size.control)
        .glass(.circle, role: .control)
        .contentShape(.circle)
        .glassControlBadge { badgeView }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityValue(badge.spoken)
  }

  @ViewBuilder private var badgeView: some View {
    switch badge {
    case .none:
      EmptyView()
    case .dot:
      Color.clear
        .frame(width: 10, height: 10)
        .glassBadge(.blushPink)
        .offset(x: -3, y: 3)
    case .count(let count):
      Text(count > 9 ? "9+" : "\(count)")
        .font(.ourioMicro.monospacedDigit())
        .padding(.horizontal, 5)
        .frame(minWidth: 18, minHeight: 18)
        .glassBadge(.blushPink)
        .offset(x: GlassMetrics.badgeOverhang, y: -GlassMetrics.badgeOverhang)
    }
  }
}

extension GlassIconButton.Badge {
  fileprivate var spoken: String {
    switch self {
    case .none, .dot: ""
    case .count(let count): count > 0 ? "\(count) unread" : ""
    }
  }
}

extension GlassIconButton where Content == GlassSymbol {
  public init(symbol: String, label: String, badge: Badge = .none, action: @escaping () -> Void) {
    self.init(label: label, badge: badge, action: action) { GlassSymbol(name: symbol) }
  }
}

/// A text style, not a drawn size, so it is rasterised at the screen's scale.
public struct GlassSymbol: View {
  let name: String

  public init(name: String) { self.name = name }

  public var body: some View {
    Image(systemName: name)
      .font(
        Look.current == .dusk
          ? .system(.body, design: .rounded, weight: .semibold) : .body.weight(.semibold)
      )
      .imageScale(.large)
      .foregroundStyle(Ink.glassGlyph)
  }
}

/// A deal shows the old price struck through after the new one.
public struct PriceButton: View {
  let price: Int
  let was: Int?
  let label: String?
  let hint: String?
  let action: () -> Void

  public init(
    _ price: Int, was: Int? = nil, label: String? = nil, hint: String? = nil,
    action: @escaping () -> Void
  ) {
    self.price = price
    self.was = was
    self.label = label
    self.hint = hint
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      HStack(alignment: .firstTextBaseline, spacing: Space.xs + 1) {
        CoinIcon(size: 16, relativeTo: .subheadline)
          .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
        Text(price, format: .number)
          .monospacedDigit()
        if let was {
          Text(was, format: .number)
            .font(.ourioCaption.monospacedDigit())
            .strikethrough()
            .opacity(0.7)
        }
      }
      .fixedSize()
      .font(.ourioCallout.weight(.bold))
      .foregroundStyle(Ink.heroInk)
      .padding(.horizontal, Space.m)
      .frame(minHeight: Size.pill)
      .background(Ink.accentFace, in: .capsule)
      .frame(minHeight: Size.control)
      .contentShape(.rect)
    }
    .buttonStyle(PressScaleStyle())
    .accessibilityLabel(label ?? was.map { "\(price) coins, was \($0)" } ?? "\(price) coins")
    .accessibilityHint(hint ?? "")
  }
}

/// Every "Try again" after a load or a send failed: the secondary capsule under an `EmptyState` or
/// in a card, or `compact` at a row's trailing edge, the height of a `PriceButton`.
public struct RetryButton: View {
  let title: String
  let compact: Bool
  let action: () -> Void

  public init(_ title: String = "Try again", compact: Bool = false, action: @escaping () -> Void) {
    self.title = title
    self.compact = compact
    self.action = action
  }

  public var body: some View {
    if compact {
      PillButton(title, symbol: "arrow.clockwise", action: action)
    } else {
      SecondaryButton(title, symbol: "arrow.clockwise", fullWidth: false, action: action)
    }
  }
}

/// The secondary action in a tight slot, beside or instead of a `PriceButton` and at its height:
/// Place on an owned item, a compact retry in a row.
public struct PillButton: View {
  let title: String
  let symbol: String?
  let fullWidth: Bool
  let action: () -> Void

  /// `fullWidth` fills its cell, so pills in a grid come out the same width.
  public init(
    _ title: String, symbol: String? = nil, fullWidth: Bool = false, action: @escaping () -> Void
  ) {
    self.title = title
    self.symbol = symbol
    self.fullWidth = fullWidth
    self.action = action
  }

  public var body: some View {
    Button(action: action) { ButtonLabel(title: title, symbol: symbol) }
      .buttonStyle(PillButtonStyle(fullWidth: fullWidth))
  }
}

public struct PillButtonStyle: ButtonStyle {
  var fullWidth: Bool
  @Environment(\.isEnabled) private var isEnabled

  public init(fullWidth: Bool = false) { self.fullWidth = fullWidth }

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.ourioCallout.weight(.semibold))
      .foregroundStyle(isEnabled ? Ink.accentText : Ink.disabledText)
      .padding(.horizontal, Space.m)
      .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Size.pill)
      .background(isEnabled ? Ink.surfaceRaised : Ink.disabledFill, in: .capsule)
      .overlay {
        if isEnabled { Capsule().strokeBorder(Ink.accentText.opacity(0.45), lineWidth: 1) }
      }
      .frame(minHeight: Size.control)
      .contentShape(.rect)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(Motion.spring(0.2), value: configuration.isPressed)
  }
}

/// A button that is on or off, like Love or Pin to wall, or one of a row of choices: a capsule the
/// height of `PrimaryButton`, washed with `tint` while on.
public struct ToggleButtonStyle: ButtonStyle {
  public static let washOpacity = 0.22

  let isOn: Bool
  let tint: Color
  @Environment(\.isEnabled) private var isEnabled

  public init(isOn: Bool, tint: Color = .honey) {
    self.isOn = isOn
    self.tint = tint
  }

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.ourioCallout.weight(.semibold))
      .foregroundStyle(isEnabled ? Ink.text : Ink.disabledText)
      .padding(.horizontal, Space.m)
      .frame(maxWidth: .infinity, minHeight: Size.button)
      .background(
        isEnabled ? (isOn ? tint.opacity(Self.washOpacity) : Ink.surfaceRaised) : Ink.disabledFill,
        in: .capsule
      )
      .contentShape(.capsule)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(Motion.spring(0.2), value: configuration.isPressed)
      .accessibilityAddTraits(isOn ? .isSelected : [])
  }
}

/// A whole row in a `GroupedSection` or a list that opens something: the row lights up while
/// pressed instead of shrinking, so its edges stay level with its neighbours.
public struct RowButtonStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .contentShape(.rect)
      .background(Ink.surfaceRaised.opacity(configuration.isPressed ? 1 : 0))
      .animation(Motion.fade(), value: configuration.isPressed)
  }
}

#Preview("Buttons") {
  ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
    VStack(spacing: Space.m) {
      PrimaryButton("Share with Alex") {}
      PrimaryButton("Pick how you feel") {}.disabled(true)
      SecondaryButton("Place", symbol: "mappin") {}
      SecondaryButton("Place", symbol: "mappin") {}.disabled(true)
      HStack {
        Button("Loved", systemImage: "heart.fill") {}.buttonStyle(
          ToggleButtonStyle(isOn: true, tint: .blushPink))
        Button("Pin to wall", systemImage: "pin") {}.buttonStyle(ToggleButtonStyle(isOn: false))
      }
      HStack {
        RetryButton {}
        RetryButton(compact: true) {}
      }
      HStack {
        GlassIconButton(symbol: "face.smiling", label: "How are you?") {}
        GlassIconButton(symbol: "tray", label: "Inbox", badge: .count(3)) {}
        PriceButton(120) {}
        PillButton("Place", symbol: "mappin") {}
      }
      HStack(spacing: Space.s) {
        PillButton("Rotate", symbol: "rotate.right", fullWidth: true) {}
        PillButton("45°", symbol: "rotate.right", fullWidth: true) {}
      }
    }
    .padding(Space.gutter)
    .background(Ink.screen)
    .environment(\.colorScheme, scheme)
  }
}
