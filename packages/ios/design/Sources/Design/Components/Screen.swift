import SwiftUI

/// A full screen with its actions pinned at the bottom: the primary is last, `Space.s` above the
/// safe area, and a secondary stacks above it, so the main action sits at the same height on every
/// page. The content scrolls under the actions and fades out there; at any text size it scrolls
/// rather than pushing them off screen.
public struct Screen<Content: View, Primary: View, Secondary: View>: View {
  let content: Content
  let primary: Primary
  let secondary: Secondary

  public init(
    @ViewBuilder content: () -> Content, @ViewBuilder primary: () -> Primary,
    @ViewBuilder secondary: () -> Secondary
  ) {
    self.content = content()
    self.primary = primary()
    self.secondary = secondary()
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.section) { content }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollIndicators(.hidden)
    .scrollBounceBehavior(.basedOnSize)
    .scrollDismissesKeyboard(.interactively)
    .bottomActions(primary: { primary }, secondary: { secondary })
    .background(Ink.screen.ignoresSafeArea())
    .tint(.honey)
  }
}

extension Screen where Secondary == EmptyView {
  public init(@ViewBuilder content: () -> Content, @ViewBuilder primary: () -> Primary) {
    self.init(content: content, primary: primary) { EmptyView() }
  }
}

extension View {
  /// The bottom action slot of `Screen`, for a full screen whose content is not a list of sections
  /// (art, a camera, a picker). Applies `ourioScrollEdges()`.
  public func bottomActions<Primary: View, Secondary: View>(
    @ViewBuilder primary: () -> Primary, @ViewBuilder secondary: () -> Secondary
  ) -> some View {
    modifier(BottomActions(primary: primary(), secondary: secondary()))
  }

  public func bottomActions<Primary: View>(@ViewBuilder primary: () -> Primary) -> some View {
    bottomActions(primary: primary) { EmptyView() }
  }
}

private struct BottomActions<Primary: View, Secondary: View>: ViewModifier {
  let primary: Primary
  let secondary: Secondary

  func body(content: Content) -> some View {
    if #available(iOS 26, macOS 26, *) {
      content
        .safeAreaBar(edge: .bottom, spacing: 0) { slot }
        .ourioScrollEdges()
    } else {
      content.safeAreaInset(edge: .bottom, spacing: 0) {
        slot.background { Ink.screen.ignoresSafeArea() }
      }
    }
  }

  private var slot: some View {
    ActionSlot {
      primary
    } secondary: {
      secondary
    }
  }
}

/// The bottom action slot itself: what `Screen` and `.bottomActions` pin, for a full screen that
/// lays out its own bottom edge (a page under a fixed header, an onboarding step). The primary is
/// last, `Space.s` over the safe area; a secondary stacks above it, and nothing is reserved under it.
public struct ActionSlot<Primary: View, Secondary: View>: View {
  let primary: Primary
  let secondary: Secondary

  public init(@ViewBuilder primary: () -> Primary, @ViewBuilder secondary: () -> Secondary) {
    self.primary = primary()
    self.secondary = secondary()
  }

  public var body: some View {
    VStack(spacing: Space.s) {
      secondary
      primary
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, Space.gutter)
    .padding(.top, Space.m)
    .padding(.bottom, Space.s)
  }
}

extension ActionSlot where Secondary == EmptyView {
  public init(@ViewBuilder primary: () -> Primary) {
    self.init(primary: primary) { EmptyView() }
  }
}

#Preview("Screen") {
  BothSchemes {
    Screen {
      SectionHeader("Name your cat")
      Field("Name", text: .constant("Mochi"))
      ForEach(0..<6, id: \.self) { index in
        Card { CardHeader("Step \(index + 1)", detail: "Something to read", symbol: "pawprint") }
      }
    } primary: {
      PrimaryButton("Continue") {}
    } secondary: {
      SecondaryButton("Skip for now") {}
    }
  }
}
