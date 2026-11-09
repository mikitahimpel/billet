import SwiftUI

/// How much a button asks for. There is one of each on a screen's main path.
public enum ButtonRank: Sendable {
  case primary
  case secondary
}

/// Full width and at least 44pt tall.
public struct ButtonLabel: View {
  private let title: String
  private let rank: ButtonRank
  private let systemImage: String?

  @Environment(\.isEnabled) private var isEnabled

  public init(_ title: String, rank: ButtonRank, systemImage: String? = nil) {
    self.title = title
    self.rank = rank
    self.systemImage = systemImage
  }

  public var body: some View {
    HStack(spacing: Spacing.small) {
      if let systemImage {
        Image(systemName: systemImage)
          .font(IconStyle.font)
          .accessibilityHidden(true)
      }
      Text(title)
        .billetType(.action)
        .multilineTextAlignment(.center)
        // At large text sizes the title wraps onto more lines instead of being cut off.
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(isEnabled ? rank.textColor : Palette.muted.color)
    .padding(.horizontal, Spacing.medium)
    .frame(maxWidth: .infinity, minHeight: Target.row)
    .contentShape(.capsule)
  }
}

extension ButtonRank {
  fileprivate var textColor: Color {
    switch self {
    case .primary: Palette.ink.color
    case .secondary: Palette.paper.color
    }
  }
}

/// The app's one text button.
public struct BilletButton: View {
  private let title: String
  private let rank: ButtonRank
  private let systemImage: String?
  private let action: () -> Void

  public init(
    _ title: String, rank: ButtonRank, systemImage: String? = nil,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.rank = rank
    self.systemImage = systemImage
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      ButtonLabel(title, rank: rank, systemImage: systemImage)
    }
    .billetButton(rank)
  }
}

extension View {
  /// Styles a `Button` or `ShareLink`: Liquid Glass on iOS 26, warm material before it.
  public func billetButton(_ rank: ButtonRank) -> some View {
    buttonStyle(ControlStyle(fill: rank == .primary ? Palette.gold : nil))
  }
}

/// A way out to the side of a screen's path, below its buttons: words alone, no surface, still a
/// 44pt target.
public struct QuietButton: View {
  private let title: String
  private let action: () -> Void

  public init(_ title: String, action: @escaping () -> Void) {
    self.title = title
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      Text(title)
        .billetType(.label)
        .underline(color: Palette.paper.color.opacity(0.4))
        .foregroundStyle(Palette.paper.color.opacity(0.85))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: Target.minimum)
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
  }
}

/// The app's one icon button: a 44pt circle holding a symbol. Selection turns it gold.
public struct IconButton: View {
  private let systemImage: String
  private let label: String
  private let isSelected: Bool
  private let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled

  public init(
    _ systemImage: String, label: String, isSelected: Bool = false,
    action: @escaping () -> Void
  ) {
    self.systemImage = systemImage
    self.label = label
    self.isSelected = isSelected
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(IconStyle.font)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .foregroundStyle(iconColor)
        .frame(width: Target.minimum, height: Target.minimum)
        .contentShape(.circle)
    }
    .buttonStyle(ControlStyle(fill: isSelected ? Palette.gold : nil))
    .accessibilityLabel(label)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .calmAnimation(Motion.quick, value: isSelected)
  }

  private var iconColor: Color {
    guard isEnabled else { return Palette.muted.color }
    return (isSelected ? Palette.ink : Palette.paper).color
  }
}

/// The one way back out of a step: a glass chevron in the top-left corner, never a big button at
/// the bottom.
public struct BackButton: View {
  private let action: () -> Void

  public init(action: @escaping () -> Void) {
    self.action = action
  }

  public var body: some View {
    IconButton("chevron.left", label: "Back", action: action)
      .accessibilityIdentifier("back")
  }
}

/// Keeps neighbouring glass controls one surface on iOS 26.
public struct GlassGroup<Content: View>: View {
  private let content: Content

  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  public var body: some View {
    if #available(iOS 26, macOS 26, *) {
      GlassEffectContainer(spacing: Spacing.small) { content }
    } else {
      content
    }
  }
}

extension View {
  /// Floats this content above the scene: Liquid Glass on iOS 26, warm material before it.
  public func floatingGlass() -> some View {
    modifier(FloatingGlass())
  }
}

private struct FloatingGlass: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26, macOS 26, *) {
      content.glassEffect(.regular, in: .capsule)
    } else {
      content.background(.ultraThinMaterial, in: .capsule)
    }
  }
}

/// The one surface of every control: glass on iOS 26, warm material before it, or `fill` when the
/// control is lit. A disabled control is never lit, so its muted label stays readable on the glass.
private struct ControlStyle: ButtonStyle {
  let fill: Swatch?

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    surface(configuration.label, fill: isEnabled ? fill : nil)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
      .animation(Motion.quick, value: configuration.isPressed)
  }

  @ViewBuilder private func surface(_ label: Configuration.Label, fill: Swatch?) -> some View {
    if #available(iOS 26, macOS 26, *) {
      if let fill {
        label.glassEffect(.regular.tint(fill.color).interactive(), in: .capsule)
      } else {
        label.glassEffect(.regular.interactive(), in: .capsule)
      }
    } else {
      label.background {
        if let fill {
          Capsule().fill(fill.color)
        } else {
          Capsule().fill(.ultraThinMaterial)
          Capsule().fill(Palette.raised.color.opacity(0.6))
        }
      }
    }
  }
}

/// Press feedback for a whole list row.
public struct RowButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.7 : 1)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
      .animation(Motion.quick, value: configuration.isPressed)
  }
}

/// Picks an ink. The hit area is 44pt; the swatch inside is 30pt.
public struct InkSwatch: View {
  private let color: Color
  private let name: String
  private let isSelected: Bool
  private let action: () -> Void

  public init(_ color: Color, name: String, isSelected: Bool, action: @escaping () -> Void) {
    self.color = color
    self.name = name
    self.isSelected = isSelected
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      ZStack {
        Circle()
          .strokeBorder(Palette.gold.color.opacity(isSelected ? 1 : 0), lineWidth: 2)
        Circle()
          .fill(color)
          .overlay {
            Circle().strokeBorder(Palette.paper.color.opacity(0.45), lineWidth: 1)
          }
          .frame(width: 30, height: 30)
      }
      .frame(width: Target.minimum, height: Target.minimum)
      .contentShape(.circle)
    }
    .buttonStyle(RowButtonStyle())
    .accessibilityLabel(name)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .calmAnimation(Motion.quick, value: isSelected)
  }
}
