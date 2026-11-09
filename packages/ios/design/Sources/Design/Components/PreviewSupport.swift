import SwiftUI

/// Pick an iPhone in the Canvas.
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

struct RoomBackdrop: View {
  var body: some View {
    LinearGradient(
      colors: [Palette.roomBackdrop.color, Palette.roomBackdropBright.color], startPoint: .top,
      endPoint: .bottom)
  }
}
