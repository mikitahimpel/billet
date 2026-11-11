import SwiftUI

/// How much of a text field's limit is used. Quiet until `warnFrom`, then it says so, and at the limit it is
/// `Ink.destructive`. Typing past the limit is cut by the field; this is what tells the person why.
public struct LimitCounter: View {
  let count: Int
  let limit: Int
  let warnFrom: Int

  public init(count: Int, limit: Int, warnFrom: Int? = nil) {
    self.count = count
    self.limit = limit
    self.warnFrom = warnFrom ?? limit * 4 / 5
  }

  public var body: some View {
    Text("\(count)/\(limit)")
      .font(.ourioCaption.weight(count >= limit ? .semibold : .regular))
      .monospacedDigit()
      .foregroundStyle(count >= limit ? Ink.destructive : Ink.textSecondary)
      .opacity(count >= warnFrom ? 1 : 0)
      .accessibilityLabel(
        count >= limit ? "Limit reached, \(limit) characters" : "\(count) of \(limit) characters"
      )
      .accessibilityHidden(count < warnFrom)
  }
}

#Preview("Limit counter") {
  BothSchemes {
    VStack(alignment: .trailing, spacing: Space.s) {
      LimitCounter(count: 12, limit: 40)
      LimitCounter(count: 34, limit: 40)
      LimitCounter(count: 40, limit: 40)
    }
    .padding(Space.gutter)
  }
}
