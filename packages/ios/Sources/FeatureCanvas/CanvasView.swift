import BilletKit
import DesignSystem
import Ink
import SwiftUI
import Wire

/// A neutral drawing surface with system controls. Placeholder styling until a design is chosen.
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
    VStack(spacing: 12) {
      HStack {
        Button("Close", action: onClose)
          .frame(minWidth: Target.minimum, minHeight: Target.minimum)
        Spacer()
        Button("Send") { onSend(store.state.drawing) }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .tint(Palette.gold.color)
          .foregroundStyle(Palette.ink.color)
          .frame(minHeight: Target.minimum)
          .disabled(store.state.drawing.isEmpty)
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
        .background(Color.white)
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
      .border(Color.secondary)

      controls
    }
    .padding()
  }

  private var controls: some View {
    VStack(spacing: 12) {
      HStack {
        ForEach(CanvasTool.allCases, id: \.self) { tool in
          Button {
            store.send(.toolSelected(tool))
          } label: {
            Text(tool.title)
              .frame(maxWidth: .infinity, minHeight: Target.minimum)
              .background(
                (store.state.tool == tool ? Palette.raisedTop : Palette.raised).color,
                in: .rect(cornerRadius: Radius.control)
              )
              .contentShape(.rect(cornerRadius: Radius.control))
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(store.state.tool == tool ? .isSelected : [])
        }
      }
      HStack(spacing: 4) {
        ForEach(CanvasColor.allCases, id: \.self) { color in
          Button {
            store.send(.colorSelected(color))
          } label: {
            Circle()
              .fill(color.color)
              .frame(width: 32, height: 32)
              .overlay(Circle().stroke(Color.secondary, lineWidth: 1))
              .overlay(
                Circle().stroke(Color.primary, lineWidth: store.state.color == color ? 3 : 0)
              )
              .frame(width: Target.minimum, height: Target.minimum)
              .contentShape(.circle)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(color.title)
        }
      }
      HStack {
        Button("Undo") { store.send(.undo) }
          .frame(minWidth: Target.minimum, minHeight: Target.minimum)
          .disabled(!store.state.canUndo)
        Button("Redo") { store.send(.redo) }
          .frame(minWidth: Target.minimum, minHeight: Target.minimum)
          .disabled(!store.state.canRedo)
        Spacer()
        Button("Clear", role: .destructive) { store.send(.cleared) }
          .frame(minWidth: Target.minimum, minHeight: Target.minimum)
          .disabled(!store.state.canClear)
      }
    }
  }
}
