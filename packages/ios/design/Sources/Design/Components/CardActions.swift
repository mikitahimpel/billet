import SwiftUI

/// A card's last row: the leading content takes the width and the trailing action keeps its own
/// size beside it. At accessibility text sizes the action goes under the content instead of
/// squeezing it.
public struct CardActions<Lead: View, Trail: View>: View {
  let lead: Lead
  let trail: Trail
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(@ViewBuilder lead: () -> Lead, @ViewBuilder trail: () -> Trail) {
    self.lead = lead()
    self.trail = trail()
  }

  public var body: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s))
      : AnyLayout(HStackLayout(alignment: .center, spacing: Space.m))
    layout {
      lead.frame(maxWidth: .infinity, alignment: .leading)
      trail.fixedSize()
    }
  }
}

#Preview("Card actions") {
  BothSchemes {
    Card {
      CardActions {
        VStack(alignment: .leading) {
          Text("Window seat").font(.ourioHeadline)
          Text("A cosy corner").font(.ourioCaption)
        }
      } trail: {
        PriceButton(120) {}
      }
    }
    .padding(Space.gutter)
  }
}
