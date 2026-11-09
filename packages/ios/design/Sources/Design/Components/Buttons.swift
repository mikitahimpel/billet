import SwiftUI

/// The one primary action of a screen: a honey capsule with `Ink.heroInk` text (white on honey is too faint to
/// read). Disabled it turns into a raised neutral capsule whose label stays readable.
public struct PrimaryButtonStyle: ButtonStyle {
  var fullWidth: Bool
  @Environment(\.isEnabled) private var isEnabled

  public init(fullWidth: Bool = true) { self.fullWidth = fullWidth }

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.nookiHeadline)
      .foregroundStyle(isEnabled ? Ink.heroInk : Ink.disabledText)
      .padding(.horizontal, Space.xl)
      .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Size.button)
      .background(isEnabled ? Color.honey : Ink.disabledFill, in: .capsule)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.spring(duration: 0.2), value: configuration.isPressed)
  }
}

/// The quieter of two buttons: honey words on a raised capsule.
public struct SecondaryButtonStyle: ButtonStyle {
  var fullWidth: Bool
  @Environment(\.isEnabled) private var isEnabled

  public init(fullWidth: Bool = true) { self.fullWidth = fullWidth }

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.nookiHeadline)
      .foregroundStyle(isEnabled ? Ink.accentText : Ink.disabledText)
      .padding(.horizontal, Space.xl)
      .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Size.button)
      .background(isEnabled ? Ink.surfaceRaised : Ink.disabledFill, in: .capsule)
      .overlay {
        if isEnabled { Capsule().strokeBorder(Ink.accentText.opacity(0.45), lineWidth: 1) }
      }
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.spring(duration: 0.2), value: configuration.isPressed)
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

/// A round `control` glass button for a header: one size, the same as the avatars and the coin pill. Its symbol
/// is a plain SF Symbol, or any view of the same size through `init(label:action:content:)`.
public struct GlassIconButton<Content: View>: View {
  /// What sits on the corner of a header button.
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
        .overlay(alignment: .topTrailing) { badgeView }
        .contentShape(.circle)
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
        .accessibilityHidden(true)
    case .count(let count):
      Text(count > 9 ? "9+" : "\(count)")
        .font(.nookiMicro.monospacedDigit())
        .padding(.horizontal, 5)
        .frame(minWidth: 18, minHeight: 18)
        .glassBadge(.blushPink)
        .offset(x: 4, y: -4)
        .accessibilityHidden(true)
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

/// A crisp SF Symbol for glass: a text style, not a drawn size, so it is rasterised at the screen's scale.
public struct GlassSymbol: View {
  let name: String

  public init(name: String) { self.name = name }

  public var body: some View {
    Image(systemName: name)
      .font(.body.weight(.semibold))
      .imageScale(.large)
      .foregroundStyle(Ink.glassGlyph)
  }
}

/// A price in coins on a honey capsule. A deal shows the old price struck through after the new one, on the same
/// baseline inside the capsule.
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
        CoinIcon(size: 16).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
        Text(price, format: .number)
          .monospacedDigit()
        if let was {
          Text(was, format: .number)
            .font(.nookiCaption.monospacedDigit())
            .strikethrough()
            .opacity(0.7)
        }
      }
      .fixedSize()
      .font(.nookiCallout.weight(.bold))
      .foregroundStyle(Ink.heroInk)
      .padding(.horizontal, Space.m)
      .frame(minHeight: 36)
      .background(Color.honey, in: .capsule)
    }
    .buttonStyle(PressScaleStyle())
    .accessibilityLabel(label ?? was.map { "\(price) coins, was \($0)" } ?? "\(price) coins")
    .accessibilityHint(hint ?? "")
  }
}

#Preview("Buttons") {
  ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
    VStack(spacing: Space.m) {
      PrimaryButton("Share with Ilya") {}
      PrimaryButton("Pick how you feel") {}.disabled(true)
      SecondaryButton("Place", symbol: "mappin") {}
      SecondaryButton("Place", symbol: "mappin") {}.disabled(true)
      HStack {
        GlassIconButton(symbol: "face.smiling", label: "How are you?") {}
        GlassIconButton(symbol: "tray", label: "Inbox", badge: .count(3)) {}
        PriceButton(120) {}
      }
    }
    .padding(Space.gutter)
    .background(Ink.screen)
    .environment(\.colorScheme, scheme)
  }
}
