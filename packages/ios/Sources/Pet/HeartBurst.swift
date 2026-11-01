import SwiftUI

/// A small heart that floats up and fades each time `trigger` changes.
///
/// A SwiftUI overlay, so it works over any scene. `tint` and `size` set the look; the partner's
/// purr uses a smaller, softer heart than a tap on your own phone.
public struct HeartBurst: View {
  private let trigger: Int
  private let size: CGFloat
  private let tint: Color
  @State private var hearts: [Int] = []

  public init(trigger: Int, size: CGFloat = 28, tint: Color = .pink) {
    self.trigger = trigger
    self.size = size
    self.tint = tint
  }

  public var body: some View {
    ZStack {
      ForEach(hearts, id: \.self) { id in
        FloatingHeart(size: size, tint: tint, drift: CGFloat((id % 5) - 2) * 10)
          .transition(.identity)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .onChange(of: trigger) { _, new in
      hearts.append(new)
      Task {
        try? await Task.sleep(for: .seconds(1.6))
        hearts.removeAll { $0 == new }
      }
    }
  }
}

private struct FloatingHeart: View {
  let size: CGFloat
  let tint: Color
  let drift: CGFloat
  @State private var risen = false

  var body: some View {
    Image(systemName: "heart.fill")
      .font(.system(size: size))
      .foregroundStyle(tint)
      .offset(x: drift, y: risen ? -90 : 0)
      .opacity(risen ? 0 : 1)
      .scaleEffect(risen ? 1.2 : 0.7)
      .onAppear { withAnimation(.easeOut(duration: 1.5)) { risen = true } }
  }
}
