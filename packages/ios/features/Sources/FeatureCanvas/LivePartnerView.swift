import CoreGraphics
import DesignSystem
import Ink
import SwiftUI
import Wire

/// Whether the partner is here, and their drawing while they make it.
public struct LivePartnerView: View {
  private let room: LiveRoom

  public init(room: LiveRoom) {
    self.room = room
  }

  public var body: some View {
    VStack(spacing: Spacing.small) {
      if let text = room.state.presenceText {
        Text(text)
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
          .accessibilityIdentifier("partnerPresence")
      }
      if !room.state.strokes.isEmpty {
        LiveStrokes(strokes: room.state.strokes)
          .frame(maxWidth: 280)
          .accessibilityLabel("Your partner's drawing, as they make it")
      }
    }
    .frame(maxWidth: .infinity)
    .calmAnimation(value: room.state.partner)
    .onChange(of: room.isOnline) { _, _ in room.syncLink() }
  }
}

extension LiveRoomMachine.State {
  /// The line under the header, or nothing when there is nothing to say.
  var presenceText: String? {
    guard isOnline else { return nil }
    switch partner {
    case .drawing: return "Your partner is drawing…"
    case .idle: return "Your partner is here"
    case .away, nil: return nil
    }
  }
}

/// Strokes on a sheet of paper, drawn off the main actor.
struct LiveStrokes: View {
  let strokes: [Stroke]
  @State private var image: CGImage?

  var body: some View {
    RoundedRectangle(cornerRadius: Radius.paper)
      .fill(Palette.paper.color)
      .overlay {
        if let image {
          Image(decorative: image, scale: 1).resizable().scaledToFit()
        }
      }
      .aspectRatio(1, contentMode: .fit)
      .clipShape(.rect(cornerRadius: Radius.paper))
      .task(id: strokes) {
        let strokes = strokes
        image = await Task.detached { NoteImage.cgImage(of: strokes, side: 560) }.value
      }
  }
}
