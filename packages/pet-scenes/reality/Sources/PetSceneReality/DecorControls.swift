import DesignSystem
import Pet
import SwiftUI

#if os(iOS)
  import UIKit
#endif

/// What the decorate controls show, read from a ``DecorSession`` each time it changes.
struct DecorStatus: Equatable {
  var hasSelection = false
  var canUndo = false
  /// The piece picked up came from the closet, so it can go back.
  var canPutAway = false
  /// Where the piece picked up would go is taken.
  var isBlocked = false

  @MainActor init(_ session: DecorSession) {
    hasSelection = session.selected != nil
    canUndo = session.history.canUndo
    canPutAway = session.selected.flatMap { session.pieces[$0]?.placement } != nil
    isBlocked = session.candidate.map { !$0.fit.isFree } ?? false
  }

  init() {}
}

/// The controls over a room while it is decorated: done and undo at the top, and at the foot the
/// tools for the piece picked up and the closet's furniture to add. The room stays in view between
/// them.
struct DecorControls: View {
  let status: DecorStatus
  let closet: [ShopItem]
  let owned: (ShopItem) -> Int
  let onUndo: () -> Void
  let onDone: () -> Void
  let onRotate: () -> Void
  let onPutAway: () -> Void
  let onAdd: (ShopItem) -> Void

  var body: some View {
    VStack(spacing: Spacing.small) {
      top
      Spacer(minLength: 0)
      hint
      bottom
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.top, Self.windowInsets.top + Spacing.small)
    .padding(.bottom, Self.windowInsets.bottom + Spacing.small)
    .animation(.snappy(duration: 0.25), value: status)
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
    HStack {
      Button(action: onUndo) {
        Label("Undo", systemImage: "arrow.uturn.backward")
          .labelStyle(.iconOnly)
          .font(.body.weight(.semibold))
          .frame(width: 44, height: 44)
          .background(.thinMaterial, in: Circle())
      }
      .buttonStyle(.plain)
      .disabled(!status.canUndo)
      .opacity(status.canUndo ? 1 : 0.45)
      .accessibilityIdentifier("decorUndo")
      Spacer(minLength: 0)
      Text("Decorating")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 4)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 0)
      Button(action: onDone) {
        Text("Done")
          .font(.body.weight(.semibold))
          .foregroundStyle(Palette.ink.color)
          .padding(.horizontal, 18)
          .frame(height: 44)
          .background(Palette.gold.color, in: Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("decorDone")
    }
  }

  private var hint: some View {
    Text(
      status.isBlocked
        ? "Something's in the way"
        : status.hasSelection
          ? "Drag to move · twist with two fingers to turn" : "Tap or drag a piece to move it"
    )
    .font(.footnote.weight(.medium))
    .foregroundStyle(.white)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(
      status.isBlocked
        ? AnyShapeStyle(Palette.clay.color.opacity(0.85)) : AnyShapeStyle(.ultraThinMaterial),
      in: Capsule()
    )
    .accessibilityIdentifier("decorHint")
  }

  @ViewBuilder private var bottom: some View {
    if status.hasSelection || !closet.isEmpty {
      VStack(alignment: .leading, spacing: Spacing.small) {
        if status.hasSelection { pieceTools }
        if !closet.isEmpty { tray }
      }
      .padding(Spacing.small)
      .frame(maxWidth: 420)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Radius.plate))
    }
  }

  private var pieceTools: some View {
    HStack(spacing: Spacing.small) {
      tool("Turn", systemImage: "arrow.clockwise", id: "decorRotate", action: onRotate)
      if status.canPutAway {
        tool("Put away", systemImage: "archivebox", id: "decorPutAway", action: onPutAway)
      }
    }
    .transition(.opacity.combined(with: .move(edge: .bottom)))
  }

  private func tool(
    _ title: String, systemImage: String, id: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .background(.regularMaterial, in: Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }

  private var tray: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("From the closet")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      ScrollView(.horizontal) {
        HStack(spacing: Spacing.small) {
          ForEach(closet) { item in
            Button {
              onAdd(item)
            } label: {
              VStack(spacing: 4) {
                Image(systemName: item.symbol)
                  .font(.title3)
                  .foregroundStyle(item.tint.color)
                  .frame(width: 52, height: 40)
                  .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                  .overlay(alignment: .topTrailing) {
                    let count = owned(item)
                    if count > 1 {
                      Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .padding(4)
                        .background(Palette.gold.color, in: Circle())
                        .offset(x: 6, y: -6)
                    }
                  }
                Text(item.name)
                  .font(.caption2)
                  .lineLimit(1)
                  .frame(width: 64)
              }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(item.name)")
            .accessibilityIdentifier("decorAdd-\(item.id)")
          }
        }
        .padding(.top, 6)
      }
      .scrollIndicators(.hidden)
    }
  }
}
