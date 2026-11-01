import DesignSystem
import FeatureInbox
import Ink
import SwiftUI

/// Home's row for a note the cat dug out from a year or a month ago.
public struct OnThisDaySection: View {
  private let notes: [NoteRecord]
  private let catName: String?

  @State private var image: CGImage?

  public init(notes: [NoteRecord], catName: String?) {
    self.notes = notes
    self.catName = catName
  }

  public var body: some View {
    TimelineView(.everyMinute) { context in
      if let pick = OnThisDay.pick(from: notes, now: context.date, calendar: .current) {
        ListRow(
          "\(catName ?? "The cat") dug out a note",
          subtitle:
            "From \(pick.span.words), \(pick.note.direction == .received ? "from your partner" : "from you")."
        ) {
          RoundedRectangle(cornerRadius: Radius.paper)
            .fill(Palette.paper.color)
            .overlay {
              if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit().padding(3)
              }
            }
            .frame(width: 44, height: 44)
            .task(id: pick.note.id) {
              let strokes = pick.note.strokes
              image = await Task.detached { NoteImage.cgImage(of: strokes, side: 132) }.value
            }
            .accessibilityHidden(true)
        } trailing: {
          EmptyView()
        }
        .card()
        .accessibilityIdentifier("onThisDay")
      }
    }
  }
}
