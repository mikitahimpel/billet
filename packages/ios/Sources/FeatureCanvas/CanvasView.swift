import BilletKit
import DesignSystem
import Ink
import SwiftUI
import Wire

/// A sheet of paper under the lamp, with the inks and tools on a lit tray below it.
public struct CanvasView: View {
  @State private var store = Store<CanvasMachine>(
    initial: CanvasMachine.State(), run: CanvasMachine.run)

  private let onClose: () -> Void
  private let onSend: ([Stroke]) -> Void

  public init(onClose: @escaping () -> Void, onSend: @escaping ([Stroke]) -> Void) {
    self.onClose = onClose
    self.onSend = onSend
  }

  public var body: some View {
    VStack(spacing: Spacing.small) {
      HStack {
        Button("Close", action: onClose)
          .buttonStyle(InlineButtonStyle())
        Spacer()
      }
      GeometryReader { geometry in
        let width = max(geometry.size.width, 1)
        Canvas { context, size in
          context.withCGContext { cgContext in
            // StrokeRenderer assumes a bottom-left origin; this context is already top-left.
            cgContext.translateBy(x: 0, y: size.height)
            cgContext.scaleBy(x: 1, y: -1)
            do {
              try StrokeRenderer.draw(store.state.visibleStrokes, in: cgContext, size: size)
            } catch {
              assertionFailure("Canvas strokes failed to render: \(error)")
            }
          }
        }
        .background(Palette.paper.color)
        .clipShape(.rect(cornerRadius: Radius.paper))
        .lampGlow()
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              let point = Point(x: value.location.x / width, y: value.location.y / width)
              store.send(store.state.inProgress == nil ? .strokeBegan(point) : .strokeMoved(point))
            }
            .onEnded { _ in store.send(.strokeEnded) }
        )
        .accessibilityLabel("Drawing canvas")
      }

      controls
    }
    .padding(Spacing.medium)
    .background { EveningBackground() }
  }

  private var controls: some View {
    VStack(spacing: Spacing.small) {
      VStack(spacing: Spacing.small) {
        HStack(spacing: Spacing.small) {
          ForEach(CanvasTool.allCases, id: \.self) { tool in
            toolButton(tool)
          }
        }
        ViewThatFits(in: .horizontal) {
          HStack(spacing: Spacing.hair) { inks }
          ScrollView(.horizontal) {
            HStack(spacing: Spacing.hair) { inks }
          }
        }
        HStack(spacing: Spacing.small) {
          Button("Undo") { store.send(.undo) }
            .buttonStyle(InlineButtonStyle())
            .disabled(!store.state.canUndo)
            .opacity(store.state.canUndo ? 1 : 0.5)
          Button("Redo") { store.send(.redo) }
            .buttonStyle(InlineButtonStyle())
            .disabled(!store.state.canRedo)
            .opacity(store.state.canRedo ? 1 : 0.5)
          Spacer()
          Button("Clear") { store.send(.cleared) }
            .buttonStyle(InlineButtonStyle())
            .disabled(!store.state.canClear)
            .opacity(store.state.canClear ? 1 : 0.5)
        }
      }
      .padding(Spacing.small)
      .litPanel(cornerRadius: Radius.control)
      Button("Send") { onSend(store.state.drawing) }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(store.state.drawing.isEmpty)
        .opacity(store.state.drawing.isEmpty ? 0.5 : 1)
    }
    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
  }

  private func toolButton(_ tool: CanvasTool) -> some View {
    let selected = store.state.tool == tool
    return Button {
      store.send(.toolSelected(tool))
    } label: {
      Text(tool.title)
        .billetType(.label)
        .foregroundStyle((selected ? Palette.ink : Palette.paper).color)
        .frame(maxWidth: .infinity, minHeight: Target.minimum)
        .background(
          (selected ? Palette.gold : Palette.raisedTop).color,
          in: .rect(cornerRadius: Radius.control)
        )
        .contentShape(.rect(cornerRadius: Radius.control))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var inks: some View {
    ForEach(CanvasColor.allCases, id: \.self) { color in
      let selected = store.state.color == color
      Button {
        store.send(.colorSelected(color))
      } label: {
        ZStack {
          Circle().strokeBorder(Palette.paper.color.opacity(selected ? 1 : 0), lineWidth: 2)
          Circle()
            .fill(color.color)
            .overlay { Circle().strokeBorder(Palette.paper.color.opacity(0.45), lineWidth: 1) }
            .frame(width: 30, height: 30)
        }
        .frame(width: Target.minimum + 4, height: Target.minimum + 4)
        .contentShape(.circle)
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)
      .accessibilityLabel(color.title)
      .accessibilityAddTraits(selected ? .isSelected : [])
    }
  }
}
