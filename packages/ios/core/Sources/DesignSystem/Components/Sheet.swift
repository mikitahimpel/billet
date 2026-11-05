import SwiftUI

/// The one ground of every sheet: the warm glass of the controls over the room, a blur of what is
/// behind under a lamp-lit wash that deepens towards the foot. It stays still, so nothing redraws
/// under a list while it scrolls.
public struct SheetGround: View {
  public init() {}

  public var body: some View {
    ZStack {
      Rectangle().fill(.ultraThinMaterial)
      LinearGradient(
        colors: [
          Palette.raisedTop.color.opacity(Self.wash.top),
          Palette.raised.color.opacity(Self.wash.middle),
          Palette.pageDeep.color.opacity(Self.wash.foot),
        ],
        startPoint: .top, endPoint: .bottom)
    }
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }

  /// How much of the lamp-lit wash covers the blur, top to foot: enough that paper text keeps its
  /// contrast over any room.
  static let wash = (top: 0.72, middle: 0.82, foot: 0.92)
}

extension EnvironmentValues {
  /// Whether this view is the content of a sheet, which ``ScreenScaffold`` and ``SheetHeader``
  /// read to leave the ground to the sheet and to offer a way to close it.
  @Entry public var isInSheet = false
}

extension View {
  /// Presents this view as the app's one kind of sheet: the warm glass ground, the grabber, and
  /// the evening's dark scheme. Every sheet goes through here, so none styles itself.
  public func billetSheet(_ detents: Set<PresentationDetent> = [.large]) -> some View {
    environment(\.isInSheet, true)
      .modifier(CountsAsSheet())
      .presentationDetents(detents)
      .presentationBackground { SheetGround() }
      .presentationDragIndicator(.visible)
      .preferredColorScheme(.dark)
  }
}

/// The top of a sheet: its title, whatever controls it keeps beside it, and the close button.
/// At large text sizes the title takes a line of its own.
public struct SheetHeader<Controls: View>: View {
  private let title: String
  private let onClose: (() -> Void)?
  private let controls: Controls

  @Environment(\.dismiss) private var dismiss

  /// - Parameter onClose: What closing does, where the presenter closes the sheet itself; by
  ///   default the sheet is dismissed.
  public init(
    _ title: String, onClose: (() -> Void)? = nil, @ViewBuilder controls: () -> Controls
  ) {
    self.title = title
    self.onClose = onClose
    self.controls = controls()
  }

  public var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: Spacing.small) {
        heading
        Spacer(minLength: Spacing.small)
        buttons
      }
      VStack(alignment: .leading, spacing: Spacing.small) {
        HStack {
          heading
          Spacer(minLength: Spacing.small)
          close
        }
        HStack(spacing: Spacing.small) { controls }
      }
    }
  }

  private var heading: some View {
    Text(title)
      .billetType(.title)
      .foregroundStyle(Palette.paper.color)
      .accessibilityAddTraits(.isHeader)
  }

  @ViewBuilder private var buttons: some View {
    controls
    close
  }

  private var close: some View {
    IconButton("xmark", label: "Close") { (onClose ?? { dismiss() })() }
      .accessibilityIdentifier("sheetClose")
  }
}

extension SheetHeader where Controls == EmptyView {
  public init(_ title: String, onClose: (() -> Void)? = nil) {
    self.init(title, onClose: onClose) { EmptyView() }
  }
}

/// Rows sharing one card.
public struct SettingsGroup<Rows: View>: View {
  private let rows: Rows

  public init(@ViewBuilder rows: () -> Rows) {
    self.rows = rows()
  }

  public var body: some View {
    VStack(spacing: 0) { rows }
      .frame(maxWidth: .infinity)
      .card()
  }
}

/// The name of a group of cards.
public struct SettingsHeading: View {
  private let title: String

  public init(_ title: String) {
    self.title = title
  }

  public var body: some View {
    Text(title)
      .billetType(.label)
      .foregroundStyle(Palette.muted.color)
      .padding(.horizontal, Spacing.medium)
      .accessibilityAddTraits(.isHeader)
  }
}

/// A short sheet that does not scroll: the header, then its content, at the margins of every
/// sheet.
public struct SheetPanel<Content: View>: View {
  private let title: String
  private let content: Content

  public init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.medium) {
      SheetHeader(title)
      content
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.top, Spacing.large)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
