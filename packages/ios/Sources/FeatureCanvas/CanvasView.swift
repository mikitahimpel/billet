import BilletKit
import Ink
import SwiftUI
import Wire

/// A neutral drawing surface with system controls. Placeholder styling until a design is chosen.
public struct CanvasView: View {
  @State private var store = Store<CanvasMachine>(
    initial: CanvasMachine.State(), run: CanvasMachine.run)

  public init() {}

  public var body: some View {
    VStack(spacing: 12) {
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
        Picker("Tool", selection: tool) {
          ForEach(CanvasTool.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
      }
      HStack(spacing: 12) {
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
          }
          .buttonStyle(.plain)
          .accessibilityLabel(color.title)
        }
      }
      HStack {
        Button("Undo") { store.send(.undo) }
          .disabled(!store.state.canUndo)
        Button("Redo") { store.send(.redo) }
          .disabled(!store.state.canRedo)
        Spacer()
        Button("Clear", role: .destructive) { store.send(.cleared) }
          .disabled(!store.state.canClear)
      }
    }
  }

  private var tool: Binding<CanvasTool> {
    Binding(get: { store.state.tool }, set: { store.send(.toolSelected($0)) })
  }
}
