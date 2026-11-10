import SwiftUI

/// The one action at the foot of a shop tile, full width and `Size.button` tall: the price to buy,
/// the coins still missing, or the owned and in-room states, which are labels and not buttons.
public struct TileButton: View {
  public enum Face: Equatable {
    case price(Int, was: Int?)
    case short(missing: Int)
    case owned
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
        .background(Color.honey, in: .capsule)
        .contentShape(.capsule)
      }
      .buttonStyle(PressScaleStyle())
      .accessibilityLabel("\(name), price \(price) coins")
      .accessibilityAddTraits(.isButton)
    case .short(let missing):
      Button(action: action) {
        HStack(spacing: Space.xs + 1) {
          CoinIcon(size: Size.pill / 2, relativeTo: .headline)
          Text("Need \(missing, format: .number) more").monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .font(.ourioHeadline)
        .foregroundStyle(Ink.text)
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
    case .inRoom:
      label("In room", symbol: "mappin", style: Ink.accentText)
        .accessibilityLabel("\(name), in your room")
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
      TileButton(.inRoom, name: "Lamp") {}
    }
    .padding(Space.gutter)
  }
}
