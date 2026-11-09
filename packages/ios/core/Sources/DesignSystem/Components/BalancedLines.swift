import SwiftUI

/// CSS's `text-wrap: balance`: the narrowest width that keeps the line count it has at full width,
/// so a short last line does not read as a stray word.
public struct BalancedLines: Layout {
  public init() {}

  public func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) -> CGSize {
    guard let text = subviews.first else { return .zero }
    let width = Self.balancedWidth(of: text, in: proposal.width)
    return text.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
  }

  public func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    subviews.first?.place(
      at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top,
      proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
  }

  /// Searches between half of `available` and all of it, which is close enough after a few steps.
  static func balancedWidth(of text: LayoutSubview, in available: CGFloat?) -> CGFloat? {
    guard let available, available.isFinite, available > 0 else { return available }
    let height = text.sizeThatFits(ProposedViewSize(width: available, height: nil)).height
    var low = available / 2
    var high = available
    for _ in 0..<8 {
      let middle = (low + high) / 2
      if text.sizeThatFits(ProposedViewSize(width: middle, height: nil)).height <= height {
        high = middle
      } else {
        low = middle
      }
    }
    return min(high.rounded(.up), available)
  }
}
