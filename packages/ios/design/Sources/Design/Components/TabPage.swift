import SwiftUI

/// What every tab root shares: the gutter, and the gap under the shared header (inbox, mood, coins, avatars) and
/// over the tab bar. The tab bar already names the tab, so a root never draws a title of its own.
public enum TabMetrics {
  public static let side: CGFloat = Space.l
  public static let top: CGFloat = Space.xs
  public static let bottom: CGFloat = Space.l
  /// How far `HeaderScrim` runs on past the header's lower edge, fading out.
  public static let scrimFade: CGFloat = 56
}

/// Behind the shared header (and its chips) of a tab root: the backdrop's warm dark through the status bar and the
/// header, fading to clear just under it, so content scrolled up there sinks away instead of meeting the glass. A
/// fixed gradient: no blur or material to redraw as the page scrolls.
public struct HeaderScrim: View {
  public init() {}

  public var body: some View {
    VStack(spacing: 0) {
      LinearGradient(
        colors: [Ink.headerScrim.opacity(0.96), Ink.headerScrim.opacity(0.9)], startPoint: .top,
        endPoint: .bottom)
      LinearGradient(
        colors: [Ink.headerScrim.opacity(0.9), Ink.headerScrim.opacity(0)], startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: TabMetrics.scrimFade)
    }
    .padding(.bottom, -TabMetrics.scrimFade)
    .ignoresSafeArea(edges: .top)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
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
  /// The vertical insets of a tab root's content, for one that lays out its own scroll view (the Shop's).
  public func tabContentInsets() -> some View {
    padding(.top, TabMetrics.top).padding(.bottom, TabMetrics.bottom)
  }
}

#Preview("Header scrim") {
  ZStack(alignment: .top) {
    Ink.headerScrim.opacity(0.6).ignoresSafeArea()
    TabPage {
      ForEach(0..<8) { index in
        Card { CardHeader("Idea \(index + 1)", detail: "Saved", symbol: "sparkles") }
      }
    }
    .safeAreaInset(edge: .top) {
      Chip("Furniture").frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Space.l)
        .background { HeaderScrim() }
    }
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
