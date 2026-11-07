import SwiftUI

/// How tall a `BilletSheet` opens.
public enum SheetSize: Sendable {
  /// As tall as its content, and `.large` too when the content outgrows the screen.
  case fit
  case medium
  case large
  /// Opens at medium and drags up to large.
  case mediumLarge
}

/// The one scaffold of every sheet: a navigation stack on `Ink.screen` with an inline, centred title.
///
/// Close is a glass `xmark` at the top trailing edge. A sheet that confirms something gets a glass honey
/// `checkmark` there instead, and its close moves to the leading edge. Pushed screens get the system's back
/// chevron. There are no "Done" or "Cancel" text pills.
public struct BilletSheet<Content: View>: View {
  let title: String
  let size: SheetSize
  let scrolls: Bool
  let confirm: (action: () -> Void, isEnabled: Bool)?
  let content: Content

  @Environment(\.dismiss) private var dismiss
  @State private var fitHeight: CGFloat = 0

  /// - Parameters:
  ///   - scrolls: Wraps the content in a scroll view with the side insets. Pass false for content that is a
  ///     `List` or a scroll view itself; it then keeps the same insets through `Page` or its own rows.
  ///   - onConfirm: Shows the confirm button and runs this when it is tapped.
  public init(
    _ title: String, size: SheetSize = .large, scrolls: Bool = true,
    onConfirm: (() -> Void)? = nil, canConfirm: Bool = true,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.size = size
    self.scrolls = scrolls
    self.confirm = onConfirm.map { ($0, canConfirm) }
    self.content = content()
  }

  public var body: some View {
    NavigationStack {
      body(of: content)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Ink.screen)
        .navigationTitle(title)
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbar }
    }
    .tint(.honey)
    .presentationDetents(detents)
    .presentationDragIndicator(.visible)
    .presentationBackground(Ink.screen)
  }

  @ViewBuilder private func body(of content: Content) -> some View {
    if scrolls {
      ScrollView {
        content
          .padding(.horizontal, Space.gutter)
          .padding(.vertical, Space.l)
          .onGeometryChange(for: CGFloat.self) {
            $0.size.height
          } action: {
            fitHeight = ceil($0)
          }
      }
      .scrollBounceBehavior(.basedOnSize)
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.interactively)
    } else {
      content
    }
  }

  private var detents: Set<PresentationDetent> {
    switch size {
    case .fit where scrolls && fitHeight > 0: [.height(fitHeight + Self.chrome), .large]
    case .fit, .large: [.large]
    case .medium: [.medium]
    case .mediumLarge: [.medium, .large]
    }
  }

  /// The navigation bar and the home indicator around the content of a fitted sheet.
  private static var chrome: CGFloat { 56 + 34 }

  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    if let confirm {
      ToolbarItem(placement: .cancellationAction) { CloseButton { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        ConfirmButton(action: confirm.action).disabled(!confirm.isEnabled)
      }
    } else {
      ToolbarItem(placement: .primaryAction) { CloseButton { dismiss() } }
    }
  }
}

/// The glass `xmark` of a sheet.
public struct CloseButton: View {
  let action: () -> Void

  public init(action: @escaping () -> Void) { self.action = action }

  public var body: some View {
    if #available(iOS 26, macOS 26, *) {
      Button(role: .close, action: action)
    } else {
      Button(action: action) { Image(systemName: "xmark") }
        .accessibilityLabel("Close")
    }
  }
}

/// The glass honey `checkmark` that confirms a sheet.
public struct ConfirmButton: View {
  let action: () -> Void

  public init(action: @escaping () -> Void) { self.action = action }

  public var body: some View {
    if #available(iOS 26, macOS 26, *) {
      Button(role: .confirm, action: action).tint(.honey)
    } else {
      Button(action: action) { Image(systemName: "checkmark") }
        .fontWeight(.semibold)
        .accessibilityLabel("Confirm")
    }
  }
}

/// A screen of sections on `Ink.screen` that scrolls as one page, for a pushed screen or the content of a sheet
/// that is not a `BilletSheet`'s own scroll view.
public struct Page<Content: View>: View {
  let content: Content

  public init(@ViewBuilder content: () -> Content) { self.content = content() }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.section) { content }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.l)
    }
    .scrollIndicators(.hidden)
    .scrollDismissesKeyboard(.interactively)
    .background(Ink.screen.ignoresSafeArea())
    .tint(.honey)
    .modifier(SoftTopEdge())
  }
}

/// Text scrolling up under the glass bar and its back button fades out instead of showing through.
private struct SoftTopEdge: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26, macOS 26, *) {
      content.scrollEdgeEffectStyle(.soft, for: .top)
    } else {
      content
    }
  }
}

#Preview("Confirming sheet") {
  Color.clear.sheet(isPresented: .constant(true)) {
    BilletSheet("Edit profile", size: .large, onConfirm: {}) {
      GroupedSection(header: "Name") {
        Row("Mikita", symbol: "person.fill", tint: .honey)
        Row("Partner", symbol: "heart.fill", tint: .blushPink)
      }
    }
  }
}

#Preview("Fitted sheet") {
  Color.clear.sheet(isPresented: .constant(true)) {
    BilletSheet("How are you?", size: .fit) {
      VStack(spacing: Space.l) {
        EmptyState(symbol: "face.smiling", title: "Pick a mood", text: "It goes to your partner.")
        PrimaryButton("Share") {}
      }
    }
  }
}
