import BilletKit
import DesignSystem
import Ink
import SwiftUI
import Wire

/// A sheet of warm paper under the lamp, with the tools in glass on their own row below it.
public struct CanvasView: View {
  @State private var store = Store<CanvasMachine>(
    initial: CanvasMachine.State(), run: CanvasMachine.run)
  @State private var choosingInk = false
  @State private var lifted: [Stroke] = []
  @State private var liftedOpacity = 0.0
  @State private var sending = false

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let prompt: String?
  private let onClose: () -> Void
  private let onSend: ([Stroke]) -> Void

  /// - Parameter prompt: Something to draw, shown beside the close button.
  public init(
    prompt: String? = nil, onClose: @escaping () -> Void, onSend: @escaping ([Stroke]) -> Void
  ) {
    self.prompt = prompt
    self.onClose = onClose
    self.onSend = onSend
  }

  public var body: some View {
    VStack(spacing: Spacing.small) {
      HStack {
        IconButton("xmark", label: "Close", action: onClose)
        Spacer()
        if let prompt {
          Text(prompt)
            .billetType(.label)
            .foregroundStyle(Palette.paperTurned.color)
            .multilineTextAlignment(.trailing)
            .accessibilityIdentifier("canvasPrompt")
        }
      }
      sheet
      tools
      BilletButton("Send", rank: .primary, action: send)
        .disabled(store.state.drawing.isEmpty || sending)
    }
    .padding(Spacing.medium)
    .background { EveningBackground() }
    .calmAnimation(value: choosingInk)
    .sensoryFeedback(.impact(flexibility: .soft), trigger: sending) { _, now in now }
    .sensoryFeedback(.selection, trigger: store.state.tool)
    .sensoryFeedback(.selection, trigger: store.state.color)
    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
  }

  /// The paper and whatever is drawn on it. Sending folds it back and lifts it off the screen.
  private var sheet: some View {
    GeometryReader { geometry in
      let width = max(geometry.size.width, 1)
      let height = max(geometry.size.height, 1)
      ZStack {
        CanvasPaper()
        StrokeLayer(strokes: lifted)
          .opacity(liftedOpacity)
          .accessibilityHidden(true)
        StrokeLayer(strokes: store.state.visibleStrokes)
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { value in
                // A drag that runs off the paper stays on its edge, so no ink lands under the tools.
                let point = Point(
                  x: min(max(value.location.x, 0), width) / width,
                  y: min(max(value.location.y, 0), height) / width)
                store.send(
                  store.state.inProgress == nil ? .strokeBegan(point) : .strokeMoved(point))
              }
              .onEnded { _ in store.send(.strokeEnded) }
          )
          .accessibilityLabel("Drawing canvas")
          .accessibilityIdentifier("drawingCanvas")
      }
      .clipShape(.rect(cornerRadius: Radius.paper))
      .rotation3DEffect(
        .degrees(sending && !reduceMotion ? 24 : 0), axis: (x: 1, y: 0, z: 0),
        anchor: .top, perspective: 0.5
      )
      .offset(y: sending && !reduceMotion ? -geometry.size.height * 1.2 : 0)
      .opacity(sending ? 0 : 1)
      .animation(.easeIn(duration: Self.sendDuration), value: sending)
    }
  }

  /// The inks take the toolbar's place, so the row never covers the paper. Picking one puts the
  /// toolbar back, including the ink already in use.
  @ViewBuilder private var tools: some View {
    if choosingInk {
      inks
        .transition(.opacity)
    } else {
      toolbar
        .transition(.opacity)
    }
  }

  private var toolbar: some View {
    GlassGroup {
      HStack(spacing: Spacing.small) {
        ForEach(CanvasTool.allCases, id: \.self) { tool in
          IconButton(tool.systemImage, label: tool.title, isSelected: store.state.tool == tool) {
            store.send(.toolSelected(tool))
          }
        }
        InkSwatch(store.state.color.color, name: "Ink colour", isSelected: choosingInk) {
          choosingInk.toggle()
        }
        .floatingGlass()
        Spacer(minLength: 0)
        IconButton("arrow.uturn.backward", label: "Undo", action: undo)
          .disabled(!store.state.canUndo)
        IconButton("arrow.uturn.forward", label: "Redo") { store.send(.redo) }
          .disabled(!store.state.canRedo)
        IconButton("trash", label: "Clear", action: clear)
          .disabled(!store.state.canClear)
      }
    }
  }

  private var inks: some View {
    HStack(spacing: 0) {
      ForEach(CanvasColor.allCases, id: \.self) { color in
        InkSwatch(color.color, name: color.title, isSelected: store.state.color == color) {
          store.send(.colorSelected(color))
          choosingInk = false
        }
        .frame(maxWidth: .infinity)
      }
    }
    .padding(.horizontal, Spacing.small)
    .floatingGlass()
  }

  private func undo() {
    fadeAway(Array(store.state.drawing.suffix(1)))
    store.send(.undo)
  }

  private func clear() {
    fadeAway(store.state.drawing)
    store.send(.cleared)
  }

  /// Lets strokes that have just left the drawing dissolve instead of vanishing.
  private func fadeAway(_ strokes: [Stroke]) {
    lifted = strokes
    liftedOpacity = 1
    withAnimation(.easeOut(duration: 0.35)) { liftedOpacity = 0 }
  }

  private func send() {
    guard !sending else { return }
    choosingInk = false
    sending = true
    let drawing = store.state.drawing
    Task {
      try? await Task.sleep(for: .seconds(Self.sendDuration))
      onSend(drawing)
    }
  }

  private static let sendDuration = 0.5
}

/// The strokes alone, over a clear ground, so the paper under them never redraws.
private struct StrokeLayer: View {
  let strokes: [Stroke]

  var body: some View {
    Canvas { context, size in
      context.withCGContext { cgContext in
        // StrokeRenderer assumes a bottom-left origin; this context is already top-left.
        cgContext.translateBy(x: 0, y: size.height)
        cgContext.scaleBy(x: 1, y: -1)
        do {
          try StrokeRenderer.draw(strokes, in: cgContext, size: size)
        } catch {
          assertionFailure("Canvas strokes failed to render: \(error)")
        }
      }
    }
  }
}

/// Warm paper with a little grain, lit from above. It takes no input, so it draws once.
private struct CanvasPaper: View {
  private static let grainCount = 1400

  var body: some View {
    ZStack {
      Palette.paper.color
      Canvas { context, size in
        var generator = SeededGenerator()
        for _ in 0..<Self.grainCount {
          let x = Double.random(in: 0...size.width, using: &generator)
          let y = Double.random(in: 0...size.height, using: &generator)
          let fleck = Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 0.8))
          context.fill(fleck, with: .color(Palette.wood.color.opacity(0.1)))
        }
      }
      LinearGradient(
        colors: [
          Palette.light.color.opacity(0.22), .clear, Palette.paperTurned.color.opacity(0.3),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
    .drawingGroup()
    .accessibilityHidden(true)
  }
}

/// The same flecks on every run, so the paper never shimmers between redraws.
private struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64 = 0x9E37_79B9_7F4A_7C15

  mutating func next() -> UInt64 {
    state ^= state << 13
    state ^= state >> 7
    state ^= state << 17
    return state
  }
}
