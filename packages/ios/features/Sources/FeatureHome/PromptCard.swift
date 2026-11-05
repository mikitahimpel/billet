import DesignSystem
import SwiftUI

/// A question or a thing to doodle, with the way into the canvas.
struct PromptCard: View {
  let title: String
  let prompt: String
  let onDraw: () -> Void

  var body: some View {
    ListRow(title, subtitle: prompt) {
      EmptyView()
    } trailing: {
      IconButton("pencil.tip", label: "Draw it", action: onDraw)
    }
    .card()
    .accessibilityElement(children: .contain)
  }
}
