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
      .foregroundStyle(isEnabled ? Ink.heroInk : Ink.textSecondary)
      .padding(.horizontal, Space.xl)
      .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Size.button)
      .background(isEnabled ? Color.honey : Ink.surfaceRaised, in: .capsule)
      .overlay { if !isEnabled { Capsule().strokeBorder(Ink.separator, lineWidth: 0.5) } }
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
      .foregroundStyle(isEnabled ? Ink.accentText : Ink.textSecondary)
      .padding(.horizontal, Space.xl)
      .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Size.button)
      .background(Ink.surfaceRaised, in: .capsule)
      .overlay(Capsule().strokeBorder(Ink.separator, lineWidth: 0.5))
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

/// A round glass button for a header: one size, the same as the avatars and the coin pill. Its symbol is a
/// plain SF Symbol, or any view of the same size through `init(label:action:content:)`.
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
        .glass(.circle, tint: Ink.glassTint, clear: true, interactive: true)
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
      Circle()
        .fill(Color.blushPink)
        .frame(width: 10, height: 10)
        .offset(x: -3, y: 3)
        .accessibilityHidden(true)
    case .count(let count):
      Text(count > 9 ? "9+" : "\(count)")
        .font(.nookiMicro.monospacedDigit())
        .foregroundStyle(Ink.heroInk)
        .padding(.horizontal, 5)
        .frame(minWidth: 18, minHeight: 18)
        .background(Color.blushPink, in: .capsule)
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
      .foregroundStyle(Ink.primary)
  }
}

/// A price in coins on a honey capsule.
public struct PriceButton: View {
  let price: Int
  let action: () -> Void

  public init(_ price: Int, action: @escaping () -> Void) {
    self.price = price
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      HStack(spacing: Space.xs + 1) {
        CoinIcon(size: 16)
        Text(price, format: .number)
          .monospacedDigit()
      }
      .font(.nookiCallout.weight(.bold))
      .foregroundStyle(Ink.heroInk)
      .padding(.horizontal, Space.m)
      .frame(minHeight: 36)
      .background(Color.honey, in: .capsule)
    }
    .buttonStyle(PressScaleStyle())
    .accessibilityLabel("\(price) coins")
  }
}

#Preview("Buttons") {
  VStack(spacing: Space.m) {
    PrimaryButton("Share with Ilya") {}
    PrimaryButton("Pick how you feel") {}.disabled(true)
    SecondaryButton("Owned · Place", symbol: "mappin") {}
    HStack {
      GlassIconButton(symbol: "face.smiling", label: "How are you?") {}
      GlassIconButton(symbol: "tray", label: "Inbox", badge: .count(3)) {}
      PriceButton(120) {}
    }
  }
  .padding(Space.gutter)
  .background(Ink.screen)
}
