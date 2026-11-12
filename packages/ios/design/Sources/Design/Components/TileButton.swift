import SwiftUI

/// The one action at the foot of a shop tile, full width and `Size.button` tall: the price to buy,
/// the coins still missing, or the owned and in-room states, which are labels and not buttons.
public struct TileButton: View {
  public enum Face: Equatable {
    case price(Int, was: Int?)
    case short(missing: Int)
    case owned
    /// A piece waiting in the closet: a button that opens the room to place it.
    case place
    /// A piece standing in the room: a button that opens the room with it chosen.
    case inRoom
  }

  let face: Face
  let name: String
  let action: () -> Void

  public init(_ face: Face, name: String, action: @escaping () -> Void) {
    self.face = face
    self.name = name
    self.action = action
  }

  public var body: some View {
    switch face {
    case .price(let price, let was):
      Button(action: action) {
        HStack(spacing: Space.xs + 1) {
          CoinIcon(size: Size.pill / 2, relativeTo: .headline)
          Text(price, format: .number).monospacedDigit()
          if let was, was > price {
            Text(was, format: .number)
              .font(.ourioCaption.monospacedDigit())
              .strikethrough()
              .opacity(0.7)
          }
        }
        .lineLimit(1)
        .font(.ourioHeadline)
        .foregroundStyle(Ink.heroInk)
        .frame(maxWidth: .infinity, minHeight: Size.button)
        .background(.honeyFace, in: .capsule)
        .overlay {
          Capsule().strokeBorder(
            LinearGradient(
              colors: [.white.opacity(0.5), .white.opacity(0)], startPoint: .top, endPoint: .center),
            lineWidth: 1)
        }
        .contentShape(.capsule)
      }
      .buttonStyle(LipButtonStyle())
      .accessibilityLabel("\(name), price \(price) coins")
      .accessibilityAddTraits(.isButton)
    case .short(let missing):
      Button(action: action) {
        HStack(spacing: Space.xs + 1) {
          CoinIcon(size: Size.pill / 2, relativeTo: .headline)
          // The short form when the whole line would reach the capsule's border, as in a narrow tile.
          ViewThatFits(in: .horizontal) {
            Text("Need \(missing, format: .number) more")
            Text("Need \(missing, format: .number)")
          }
          .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .font(.ourioHeadline)
        .foregroundStyle(Ink.text)
        .padding(.horizontal, Space.m)
        .frame(maxWidth: .infinity, minHeight: Size.button)
        .background(Ink.surfaceRaised, in: .capsule)
        .overlay { Capsule().strokeBorder(Color.honey, lineWidth: 2) }
        .contentShape(.capsule)
      }
      .buttonStyle(PressScaleStyle())
      .accessibilityLabel("\(name), needs \(missing) more coins")
      .accessibilityHint("Opens Coins")
    case .owned:
      label("Owned", symbol: "checkmark", style: Ink.textSecondary)
        .accessibilityLabel("\(name), owned")
    case .place:
      Button(action: action) {
        Label("Place", systemImage: "mappin")
          .font(.ourioHeadline)
          .foregroundStyle(Ink.accentText)
          .frame(maxWidth: .infinity, minHeight: Size.button)
          .background(Ink.surfaceRaised, in: .capsule)
          .overlay { Capsule().strokeBorder(Ink.accentText.opacity(0.45), lineWidth: 1) }
          .contentShape(.capsule)
      }
      .buttonStyle(PressScaleStyle())
      .accessibilityLabel("Place \(name)")
      .accessibilityHint("Opens the room")
    case .inRoom:
      Button(action: action) {
        label("In room", symbol: "mappin", style: Ink.accentText)
          .contentShape(.capsule)
      }
      .buttonStyle(PressScaleStyle())
      .accessibilityLabel("\(name), in your room")
      .accessibilityHint("Opens the room to move it")
    }
  }

  private func label(_ title: String, symbol: String, style: Color) -> some View {
    Label(title, systemImage: symbol)
      .font(.ourioHeadline)
      .foregroundStyle(style)
      .frame(maxWidth: .infinity, minHeight: Size.button)
      .accessibilityElement(children: .ignore)
  }
}

#Preview("Tile button") {
  BothSchemes {
    VStack(spacing: Space.m) {
      TileButton(.price(90, was: 120), name: "Lamp") {}
      TileButton(.short(missing: 40), name: "Lamp") {}
      TileButton(.owned, name: "Lamp") {}
      TileButton(.place, name: "Lamp") {}
      TileButton(.inRoom, name: "Lamp") {}
    }
    .padding(Space.gutter)
  }
}

/// A chunky button: a `honeyDeep` lip under the face that the face sinks onto while pressed. A flat fill and a
/// shape-only lip, so there is no blur or shadow to draw.
public struct LipButtonStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .offset(y: configuration.isPressed ? Lip.depth : 0)
      .background(alignment: .bottom) {
        Capsule().fill(Color.honeyDeep).offset(y: Lip.depth)
      }
      .padding(.bottom, Lip.depth)
      .animation(Motion.spring(0.12), value: configuration.isPressed)
  }
}

enum Lip {
  static let depth: CGFloat = 3
}
