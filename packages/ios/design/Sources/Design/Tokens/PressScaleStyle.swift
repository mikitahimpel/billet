import SwiftUI

public struct PressScaleStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.95 : 1)
      .brightness(configuration.isPressed ? -0.04 : 0)
      .animation(.spring(duration: 0.2), value: configuration.isPressed)
  }
}
