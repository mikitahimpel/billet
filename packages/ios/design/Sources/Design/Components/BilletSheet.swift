import SwiftUI

/// What a `BilletSheet` stands on: the app's screen colour, or glass over whatever is behind, the arm a perf run
/// measures a sheet over the live room with.
public enum SheetGroundStyle: Sendable {
  case opaque
  case glass
}

extension EnvironmentValues {
  @Entry public var sheetGround: SheetGroundStyle = .opaque
}

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
///
/// The system draws both buttons as toolbar items. With `hasChanges` the confirm button stays disabled until
/// something changed, closing asks "Discard changes?" and a swipe down is blocked while there are changes.
public struct BilletSheet<Content: View>: View {
  /// Which edge of the toolbar the close button sits on.
  enum ClosePlacement: Equatable {
    case leading
    case trailing

    init(confirms: Bool) { self = confirms ? .leading : .trailing }
  }

  let title: String
  let subtitle: String?
  let hasChanges: Bool?
  let size: SheetSize
  let scrolls: Bool
  let confirm: (action: () -> Void, isEnabled: Bool)?
  let content: Content

  @Environment(\.dismiss) private var dismiss
  @Environment(\.sheetGround) private var ground
  @State private var fitHeight: CGFloat = 0
  @State private var askingToDiscard = false

  /// - Parameters:
  ///   - scrolls: Wraps the content in a scroll view with the side insets. Pass false for content that is a
  ///     `List` or a scroll view itself; it then keeps the same insets through `Page` or its own rows.
  ///   - subtitle: A count or a short line under the title, in the same toolbar slot.
  ///   - hasChanges: For a sheet that edits something: false disables confirm, true makes close ask first.
  ///   - onConfirm: Shows the confirm button and runs this when it is tapped.
  public init(
    _ title: String, subtitle: String? = nil, size: SheetSize = .large, scrolls: Bool = true,
    hasChanges: Bool? = nil, onConfirm: (() -> Void)? = nil, canConfirm: Bool = true,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.subtitle = subtitle
    self.hasChanges = hasChanges
    self.size = size
    self.scrolls = scrolls
    self.confirm = onConfirm.map { ($0, canConfirm) }
    self.content = content()
  }

  public var body: some View {
    NavigationStack {
      body(of: content)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ground == .glass ? Color.clear : Ink.screen)
        .navigationTitle(subtitle == nil ? title : "")
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbar }
        .confirmationDialog(
          "Discard changes?", isPresented: $askingToDiscard, titleVisibility: .visible
        ) {
          Button("Discard changes", role: .destructive) { dismiss() }
          Button("Keep editing", role: .cancel) {}
        }
    }
    .interactiveDismissDisabled(hasChanges ?? false)
    .tint(.honey)
    .presentationDetents(detents)
    .presentationDragIndicator(.visible)
    .presentationBackground { groundView }
  }

  @ViewBuilder private var groundView: some View {
    if ground == .glass {
      Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
    } else {
      Ink.screen.ignoresSafeArea()
    }
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
      .softScrollEdges()
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

  private func close() {
    if hasChanges == true { askingToDiscard = true } else { dismiss() }
  }

  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    if let subtitle {
      ToolbarItem(placement: .principal) { SheetSubtitle(title: title, subtitle: subtitle) }
    }
    switch ClosePlacement(confirms: confirm != nil) {
    case .leading:
      ToolbarItem(placement: .cancellationAction) { CloseButton(action: close) }
    case .trailing:
      ToolbarItem(placement: .primaryAction) { CloseButton(action: close) }
    }
    if let confirm {
      ToolbarItem(placement: .confirmationAction) {
        ConfirmButton(action: confirm.action).disabled(!confirm.isEnabled || hasChanges == false)
      }
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

/// The title of a sheet with a count or a line under it, in the toolbar's one title slot.
struct SheetSubtitle: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(spacing: 0) {
      Text(title).font(.nookiHeadline).foregroundStyle(Ink.text)
      Text(subtitle).font(.nookiMicro).foregroundStyle(Ink.textSecondary).monospacedDigit()
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
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
    .softScrollEdges()
  }
}

extension View {
  /// Content scrolling out under a bar, the header or the tab bar fades out instead of being cut off hard
  /// (iOS 26's scroll edge effect); every scroll view of the app uses this, `Page` and `BilletSheet` already do.
  @ViewBuilder public func softScrollEdges() -> some View {
    if #available(iOS 26, macOS 26, *) {
      scrollEdgeEffectStyle(.soft, for: .top).scrollEdgeEffectStyle(.soft, for: .bottom)
    } else {
      self
    }
  }
}

/// What a sheet looks like inside, drawn inline: the Canvas cannot show a presented sheet.
private struct InlineSheet<Content: View>: View {
  let title: String
  let confirms: Bool
  let content: Content

  init(_ title: String, confirms: Bool = false, @ViewBuilder content: () -> Content) {
    self.title = title
    self.confirms = confirms
    self.content = content()
  }

  var body: some View {
    NavigationStack {
      ScrollView { content.padding(Space.gutter) }
        .background(Ink.screen)
        .navigationTitle(title)
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
          if confirms {
            ToolbarItem(placement: .cancellationAction) { CloseButton {} }
            ToolbarItem(placement: .confirmationAction) { ConfirmButton {} }
          } else {
            ToolbarItem(placement: .primaryAction) { CloseButton {} }
          }
        }
    }
    .tint(.honey)
  }
}

#Preview("Confirming sheet") {
  BothSchemes {
    InlineSheet("Edit profile", confirms: true) {
      GroupedSection(header: "Name") {
        Row("Mikita", symbol: "person.fill")
        Row("Partner", symbol: "heart.fill", tint: .blushPink)
      }
    }
  }
}

#Preview("Informational sheet") {
  BothSchemes {
    InlineSheet("How are you?") {
      VStack(spacing: Space.l) {
        EmptyState(symbol: "face.smiling", title: "Pick a mood", text: "It goes to your partner.")
        PrimaryButton("Share") {}
      }
    }
  }
}
