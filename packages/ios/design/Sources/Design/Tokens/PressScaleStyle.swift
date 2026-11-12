import SwiftUI

public struct PressScaleStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .brightness(configuration.isPressed ? -0.06 : 0)
      .animation(Motion.spring(0.2), value: configuration.isPressed)
  }
}
