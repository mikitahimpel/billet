import SwiftUI

/// What a `BilletSheet` stands on: the screen colour, or glass over whatever is behind.
public enum SheetGroundStyle: Sendable {
  case opaque
  case glass
}

extension EnvironmentValues {
  @Entry public var sheetGround: SheetGroundStyle = .opaque
}

public enum SheetSize: Sendable {
  /// As tall as its content, and `.large` too when the content outgrows the screen.
  case fit
  case medium
  case large
  /// Opens at medium and drags up to large.
  case mediumLarge
}

/// Close sits trailing; with `onConfirm` a honey checkmark takes that edge and close moves leading.
/// A sheet's own toolbar items go on the content: a `.toolbar` on the `BilletSheet` itself sits
/// outside its navigation stack and is never drawn.
public struct BilletSheet<Content: View>: View {
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
  ///   - scrolls: Pass false for content that is a `List` or a scroll view itself.
  ///   - hasChanges: False disables confirm; true makes close ask first and blocks swipe-down.
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
    #if canImport(UIKit)
      // Before the stack makes its bar, which takes the fonts it finds then.
      let _ = NavigationBarStyle.apply()
    #endif
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

struct SheetSubtitle: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(spacing: 0) {
      Text(title).font(.ourioHeadline).foregroundStyle(Ink.text)
      Text(subtitle).font(.ourioMicro).foregroundStyle(Ink.textSecondary).monospacedDigit()
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

/// A pushed screen, or a sheet's content that is not a `BilletSheet`'s own scroll view.
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
  /// iOS 26 soft scroll edges; every scroll view uses this, `Page` and `BilletSheet` already do.
  @ViewBuilder public func softScrollEdges() -> some View {
    if #available(iOS 26, macOS 26, *) {
      scrollEdgeEffectStyle(.soft, for: .top).scrollEdgeEffectStyle(.soft, for: .bottom)
    } else {
      self
    }
  }
}

extension View {
  /// Pins `header` (a sheet's chips, search field or subtitle) over the top of this scroll view. The
  /// content scrolls under it and fades out there as it does under the bars, on the sheet's own
  /// ground, instead of being cut at the header's lower edge. Applies `softScrollEdges()`.
  public func scrollHeader<Header: View>(@ViewBuilder _ header: () -> Header) -> some View {
    modifier(ScrollHeader(header: header()))
  }
}

private struct ScrollHeader<Header: View>: ViewModifier {
  let header: Header
  @Environment(\.sheetGround) private var ground

  func body(content: Content) -> some View {
    if #available(iOS 26, macOS 26, *) {
      content
        .safeAreaBar(edge: .top, spacing: 0) { header }
        .softScrollEdges()
    } else {
      content.safeAreaInset(edge: .top, spacing: 0) { header.background { groundView } }
    }
  }

  @ViewBuilder private var groundView: some View {
    switch ground {
    case .opaque: Ink.screen
    case .glass: Rectangle().fill(.ultraThinMaterial)
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

#Preview("Sheet with a pinned header") {
  BothSchemes {
    NavigationStack {
      ScrollView {
        VStack(spacing: Space.m) {
          ForEach(0..<12, id: \.self) { index in
            Card {
              CardHeader("Event \(index + 1)", detail: "In \(index) days", symbol: "calendar")
            }
          }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.s)
      }
      .scrollHeader {
        HStack(spacing: Space.s) {
          FilterChip("Soon", isSelected: true) {}
          FilterChip("Month", isSelected: false) {}
          Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.s)
      }
      .background(Ink.screen)
      .navigationTitle("Calendar")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
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
