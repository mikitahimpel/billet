import DesignSystem
import SwiftUI

#if os(iOS)
  import UIKit
#endif

/// What the decorate controls show, read from a ``DecorSession`` each time it changes.
struct DecorStatus: Equatable {
  /// The name of the piece picked up.
  var selected: String?
  /// What the piece picked up is called, for the toolbar.
  var title: String?
  /// A finger is moving or turning the piece picked up.
  var isHolding = false
  var canUndo = false
  /// The piece picked up came from the closet, so it can go back.
  var canPutAway = false
  /// Where the piece picked up would go is taken.
  var isBlocked = false
  /// The piece picked up can be turned; a throw hanging over the seat's edge only slides.
  var canTurn = true

  var hasSelection: Bool { selected != nil }

  @MainActor init(_ session: DecorSession, title: (String) -> String? = { _ in nil }) {
    selected = session.selected
    self.title = session.selected.flatMap(title)
    isHolding = session.isDragging || session.isTurning
    canUndo = session.history.canUndo
    canPutAway = session.selected.flatMap { session.pieces[$0]?.placement } != nil
    isBlocked = session.candidate.map { !$0.fit.isFree } ?? false
    canTurn = session.selected.map(session.canTurn) ?? true
  }

  init() {}

  /// Whether going from `old` to this status picks a piece up or sets one down, for the haptic.
  func grip(from old: DecorStatus) -> Grip? {
    if selected != old.selected { return selected == nil ? .drop : .pickUp }
    guard hasSelection, isHolding != old.isHolding else { return nil }
    return isHolding ? .pickUp : .drop
  }

  enum Grip { case pickUp, drop }
}

/// The controls over a room while it is decorated. At the top, undo and Done on one strip of
/// glass. At the foot, only when a piece is picked up, a small glass toolbar naming it with what
/// can be done to it; otherwise a slim way to add more. The room stays in view between them.
struct DecorControls: View {
  let status: DecorStatus
  let onUndo: () -> Void
  let onDone: () -> Void
  let onRotate: () -> Void
  let onPutAway: () -> Void
  /// Opens the closet to add furniture, or `nil` when the room takes none.
  var onAddItems: (() -> Void)?
  /// Puts every piece back where the room first had it, or `nil` when the room can't.
  var onReset: (() -> Void)?

  /// Whether the drag-and-twist hint has been shown once already.
  @AppStorage("decorGestureHintShown") private var hintShown = false
  @State private var showsHint = false

  var body: some View {
    VStack(spacing: Spacing.small) {
      top
      Spacer(minLength: 0)
      if showsHint {
        hint.transition(.opacity)
      }
      bottom
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.top, Self.windowInsets.top + Spacing.small)
    .padding(.bottom, Self.windowInsets.bottom + Spacing.small)
    .animation(.snappy(duration: 0.25), value: status)
    .animation(.easeOut(duration: 0.6), value: showsHint)
    .task(id: status.hasSelection) { await showHintOnce() }
  }

  /// The window's safe area. The rooms are drawn edge to edge and their hosts let them ignore the
  /// safe area, so the controls keep clear of the status bar and the home indicator themselves.
  private static var windowInsets: (top: CGFloat, bottom: CGFloat) {
    #if os(iOS)
      let window = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
      return (window?.safeAreaInsets.top ?? 0, window?.safeAreaInsets.bottom ?? 0)
    #else
      return (0, 0)
    #endif
  }

  private var top: some View {
    GlassGroup {
      HStack(spacing: Spacing.small) {
        IconButton("arrow.uturn.backward", label: "Undo", action: onUndo)
          .disabled(!status.canUndo)
          .accessibilityIdentifier("decorUndo")
        if let onReset { more(onReset) }
        Spacer(minLength: 0)
        Button(action: onDone) {
          Text("Done")
            .billetType(.action)
            .foregroundStyle(Palette.ink.color)
            .padding(.horizontal, Spacing.medium + Spacing.hair)
            .frame(height: Target.minimum)
            .contentShape(.capsule)
        }
        .billetButton(.primary)
        .accessibilityHint("Stops decorating")
        .accessibilityIdentifier("decorDone")
      }
    }
  }

  /// A glass circle holding what is done less often, behind one more tap: putting the room back.
  private func more(_ onReset: @escaping () -> Void) -> some View {
    Menu {
      Button("Reset layout", systemImage: "arrow.counterclockwise", role: .destructive) {
        onReset()
      }
      .accessibilityIdentifier("decorReset")
    } label: {
      Image(systemName: "ellipsis")
        .font(IconStyle.font)
        .foregroundStyle(Palette.paper.color)
        .frame(width: Target.minimum, height: Target.minimum)
        .contentShape(.circle)
    }
    .billetButton(.secondary)
    .accessibilityLabel("More")
    .accessibilityIdentifier("decorMore")
  }

  /// The first time a piece is picked up, how to move it, fading after a few seconds.
  private func showHintOnce() async {
    guard status.hasSelection, !hintShown else { return }
    hintShown = true
    showsHint = true
    try? await Task.sleep(for: .seconds(4))
    showsHint = false
  }

  private var hint: some View {
    Text("Drag to move · twist to turn")
      .billetType(.caption)
      .foregroundStyle(Palette.paper.color)
      .padding(.horizontal, Spacing.medium)
      .padding(.vertical, Spacing.small)
      .floatingGlass()
      .allowsHitTesting(false)
      .accessibilityIdentifier("decorHint")
  }

  @ViewBuilder private var bottom: some View {
    if status.hasSelection {
      toolbar
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
    } else if let onAddItems {
      Button(action: onAddItems) {
        Label("Add items", systemImage: "plus")
          .billetType(.action)
          .foregroundStyle(Palette.paper.color)
          .padding(.horizontal, Spacing.medium)
          .frame(height: Target.minimum)
          .contentShape(.capsule)
      }
      .billetButton(.secondary)
      .accessibilityIdentifier("decorAddItems")
      .transition(.opacity)
    } else {
      Text("Tap a piece to move it")
        .billetType(.caption)
        .foregroundStyle(Palette.paper.color)
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
        .floatingGlass()
        .accessibilityIdentifier("decorIdleHint")
        .transition(.opacity)
    }
  }

  /// The piece picked up, by name, with Turn 90° and, for closet furniture, Put away.
  private var toolbar: some View {
    HStack(spacing: 0) {
      pieceName
        .padding(.leading, Spacing.medium)
        .padding(.trailing, Spacing.small)
      Rectangle()
        .fill(Palette.paper.color.opacity(0.22))
        .frame(width: 1, height: Spacing.medium + Spacing.hair)
        .accessibilityHidden(true)
      if status.canTurn {
        tool("Turn 90°", systemImage: "arrow.clockwise", id: "decorRotate", action: onRotate)
      }
      if status.canPutAway {
        tool("Put away", systemImage: "tray.and.arrow.down", id: "decorPutAway", action: onPutAway)
      }
    }
    .frame(height: Target.minimum)
    .floatingGlass()
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder private var pieceName: some View {
    if status.isBlocked {
      Label("No room here", systemImage: "exclamationmark.circle.fill")
        .billetType(.label)
        .foregroundStyle(Palette.clayLit.color)
        .lineLimit(1)
        .accessibilityIdentifier("decorBlocked")
    } else {
      Text(status.title ?? "Piece")
        .billetType(.label)
        .foregroundStyle(Palette.paper.color)
        .lineLimit(1)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("decorPieceName")
    }
  }

  private func tool(
    _ title: String, systemImage: String, id: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .billetType(.label)
        .fontWeight(.semibold)
        .foregroundStyle(Palette.paper.color)
        .lineLimit(1)
        .padding(.horizontal, Spacing.medium - Spacing.hair)
        .frame(height: Target.minimum)
        .contentShape(.capsule)
    }
    .buttonStyle(RowButtonStyle())
    .accessibilityIdentifier(id)
  }
}
