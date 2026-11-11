import SwiftUI

/// What every tab root shares: the gutter, and the gap under the shared header (inbox, mood, coins, avatars) and
/// over the tab bar. The tab bar already names the tab, so a root never draws a title of its own.
public enum TabMetrics {
  public static let side: CGFloat = Space.l
  public static let top: CGFloat = Space.xs
  public static let bottom: CGFloat = Space.l
}

/// A tab root that scrolls: its content starts right under the shared header, at the same spot on every tab.
public struct TabPage<Content: View>: View {
  let spacing: CGFloat
  let content: Content

  public init(spacing: CGFloat = Space.m, @ViewBuilder content: () -> Content) {
    self.spacing = spacing
    self.content = content()
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: spacing) { content }
        .padding(.horizontal, TabMetrics.side)
        .tabContentInsets()
    }
    .scrollIndicators(.hidden)
    .softScrollEdges()
  }
}

extension View {
  /// The vertical insets of a tab root's content, for one that lays out its own scroll view (the Shop's pinned chips).
  public func tabContentInsets() -> some View {
    padding(.top, TabMetrics.top).padding(.bottom, TabMetrics.bottom)
  }
}

#Preview("Tab page") {
  BothSchemes {
    TabPage {
      Card { CardHeader("Anniversary", detail: "In 12 days", symbol: "heart.fill") }
      Card { CardHeader("A weekend away", detail: "3 ideas saved", symbol: "airplane") }
    }
  }
}
