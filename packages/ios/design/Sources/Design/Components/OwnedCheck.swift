import SwiftUI

/// A honey check on the corner of a piece the pair already owns.
public struct OwnedCheck: View {
  public init() {}

  public var body: some View {
    Image(systemName: "checkmark.circle.fill")
      .font(.ourioCallout)
      .symbolRenderingMode(.palette)
      .foregroundStyle(Ink.heroInk, Color.honey)
      .background(Circle().fill(Ink.well).padding(1))
      .accessibilityHidden(true)
  }
}
