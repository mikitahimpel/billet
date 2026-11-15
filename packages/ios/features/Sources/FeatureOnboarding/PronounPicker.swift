import Design
import Pet
import SwiftUI

#if canImport(UIKit)
  /// One of she / he / they, in a row that falls back to a column where the labels don't fit.
  public struct PronounPicker: View {
    let selection: CatPronouns
    var choose: (CatPronouns) -> Void

    public init(selection: CatPronouns, choose: @escaping (CatPronouns) -> Void) {
      self.selection = selection
      self.choose = choose
    }

    public var body: some View {
      ViewThatFits(in: .horizontal) {
        ChipRow(spacing: Space.s) { options }
        VStack(spacing: Space.s) { options }
      }
      .sensoryFeedback(.selection, trigger: selection)
    }

    private var options: some View {
      ForEach(CatPronouns.allCases, id: \.self) { pronouns in
        Button {
          choose(pronouns)
        } label: {
          Text(pronouns.label).lineLimit(1)
        }
        .buttonStyle(ToggleButtonStyle(isOn: selection == pronouns))
        .accessibilityIdentifier("pronouns-\(pronouns.rawValue)")
      }
    }
  }

  /// Chips in one row. Its ideal width is the sum of their one-line widths, so `ViewThatFits` drops
  /// it once a label would not fit; given more, the chips share it as ``ChipRowWidths`` says. An
  /// `HStack` would split the row into equal parts and cut the widest label.
  struct ChipRow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
      let ideal = ideal(subviews)
      let gaps = spacing * CGFloat(max(0, subviews.count - 1))
      let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
      guard let width = proposal.width, width.isFinite else {
        return CGSize(width: ideal.reduce(0, +) + gaps, height: height)
      }
      return CGSize(width: width, height: height)
    }

    func placeSubviews(
      in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
      let widths = ChipRowWidths.widths(
        ideal: ideal(subviews), available: bounds.width, spacing: spacing)
      var x = bounds.minX
      for (subview, width) in zip(subviews, widths) {
        subview.place(
          at: CGPoint(x: x, y: bounds.minY),
          proposal: ProposedViewSize(width: width, height: bounds.height))
        x += width + spacing
      }
    }

    /// Whole points, so a chip given exactly its own width never rounds into an ellipsis.
    private func ideal(_ subviews: Subviews) -> [CGFloat] {
      subviews.map { $0.sizeThatFits(.unspecified).width.rounded(.up) }
    }
  }
#endif
