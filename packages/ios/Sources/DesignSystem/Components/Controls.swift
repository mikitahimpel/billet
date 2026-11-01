import SwiftUI

/// The one primary action on a screen: gold, full width, dark text.
public struct PrimaryButtonStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .billetType(.heading)
      .foregroundStyle(Palette.ink.color)
      .multilineTextAlignment(.center)
      .padding(.horizontal, Spacing.medium)
      .padding(.vertical, Spacing.small)
      .frame(maxWidth: .infinity, minHeight: Target.primary)
      .background(Palette.gold.color, in: .rect(cornerRadius: Radius.control))
      .lampGlow()
      .opacity(configuration.isPressed ? 0.85 : 1)
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .animation(Motion.quick, value: configuration.isPressed)
  }
}

/// The quieter action beside a primary one: a lit panel with cream text.
public struct SecondaryButtonStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .billetType(.body)
      .foregroundStyle(Palette.paper.color)
      .multilineTextAlignment(.center)
      .padding(.horizontal, Spacing.medium)
      .padding(.vertical, Spacing.small)
      .frame(maxWidth: .infinity, minHeight: Target.minimum)
      .background(Palette.raised.color, in: .rect(cornerRadius: Radius.control))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.control)
          .strokeBorder(Palette.lightWarm.color.opacity(Glow.edgeOpacity), lineWidth: 1)
      }
      .contentShape(.rect(cornerRadius: Radius.control))
      .opacity(configuration.isPressed ? 0.75 : 1)
      .animation(Motion.quick, value: configuration.isPressed)
  }
}

/// A small action that sits inside a row or a bar: text on the upper rung, at least 44pt tall.
public struct InlineButtonStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .billetType(.label)
      .foregroundStyle(Palette.paper.color)
      .padding(.horizontal, Spacing.medium)
      .frame(minHeight: Target.minimum)
      .background(Palette.raisedTop.color, in: .rect(cornerRadius: Radius.control))
      .contentShape(.rect(cornerRadius: Radius.control))
      .opacity(configuration.isPressed ? 0.75 : 1)
      .animation(Motion.quick, value: configuration.isPressed)
  }
}

/// A square tool on a tray. Selection lifts it one rung and strengthens its edge.
public struct ToolButtonStyle: ButtonStyle {
  private let isSelected: Bool

  public init(isSelected: Bool = false) {
    self.isSelected = isSelected
  }

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(Palette.paper.color)
      .frame(width: 56, height: 56)
      .background(
        (isSelected ? Palette.raisedTop : Palette.raised).color,
        in: .rect(cornerRadius: Radius.control)
      )
      .overlay {
        RoundedRectangle(cornerRadius: Radius.control)
          .strokeBorder(Palette.paper.color.opacity(isSelected ? 0.6 : 0), lineWidth: 1)
      }
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}

/// A drawn icon, in the same stroke weight as the rest of the tool set.
public struct ToolIcon: View {
  public enum Kind: Sendable {
    case brush
    case undo
  }

  private let kind: Kind

  public init(_ kind: Kind) {
    self.kind = kind
  }

  public var body: some View {
    Canvas { context, size in
      let scale = size.width / 28
      context.scaleBy(x: scale, y: scale)
      context.stroke(
        ScenePath.parse(Self.data(for: kind)),
        with: .color(Palette.paper.color),
        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
      )
    }
    .frame(width: 28, height: 28)
    .accessibilityHidden(true)
  }

  private static func data(for kind: Kind) -> String {
    switch kind {
    case .brush:
      "M23 4 L12 15 M15 18 L10 13 M10 13 C6 14 8 18 4 22 C10 24 15 22 15 18"
    case .undo:
      "M10 6 L5 11 L10 16 M5 11 H17 C21 11 23 14 23 17 C23 20 21 23 17 23 H12"
    }
  }
}

/// One ink on the tray.
public enum InkChoice: CaseIterable, Sendable {
  case ink
  case clay
  case green
  case gold

  /// The colour it lays on paper. The swatch shows exactly this.
  public var swatch: Swatch {
    switch self {
    case .ink: Palette.ink
    case .clay: Palette.clayLit
    case .green: Palette.greenLit
    case .gold: Palette.inkGold
    }
  }

  fileprivate var name: LocalizedStringResource {
    switch self {
    case .ink: LocalizedStringResource("Ink", bundle: .atURL(Bundle.module.bundleURL))
    case .clay: LocalizedStringResource("Clay", bundle: .atURL(Bundle.module.bundleURL))
    case .green: LocalizedStringResource("Green", bundle: .atURL(Bundle.module.bundleURL))
    case .gold: LocalizedStringResource("Gold", bundle: .atURL(Bundle.module.bundleURL))
    }
  }

  /// The darkest ink would vanish on the tray, so it wears a ring.
  fileprivate var needsRing: Bool {
    switch self {
    case .ink: true
    case .clay, .green, .gold: false
    }
  }
}

/// Picks an ink. The hit area is 48pt; the swatch inside is 30pt.
public struct InkSwatch: View {
  private let choice: InkChoice
  private let isSelected: Bool
  private let action: () -> Void

  public init(_ choice: InkChoice, isSelected: Bool, action: @escaping () -> Void) {
    self.choice = choice
    self.isSelected = isSelected
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      ZStack {
        Circle()
          .strokeBorder(Palette.paper.color.opacity(isSelected ? 1 : 0), lineWidth: 2)
        Circle()
          .fill(choice.swatch.color)
          .overlay {
            Circle()
              .strokeBorder(
                Palette.paper.color.opacity(choice.needsRing ? 0.45 : 0),
                lineWidth: 2
              )
          }
          .frame(width: 30, height: 30)
      }
      .frame(width: 48, height: 48)
      .contentShape(.circle)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(choice.name))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
