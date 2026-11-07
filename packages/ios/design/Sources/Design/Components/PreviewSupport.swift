import SwiftUI

/// Draws its content in light and in dark, one above the other, for a preview. Pick an iPhone in the Canvas.
struct BothSchemes<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) { self.content = content() }

  var body: some View {
    VStack(spacing: 0) {
      ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
        content
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Ink.screen)
          .environment(\.colorScheme, scheme)
      }
    }
  }
}

/// A busy dark backdrop like the room, for controls that float over the scene.
struct RoomBackdrop: View {
  var body: some View {
    LinearGradient(
      colors: [Palette.roomBackdrop.color, Palette.roomBackdropBright.color], startPoint: .top,
      endPoint: .bottom)
  }
}
