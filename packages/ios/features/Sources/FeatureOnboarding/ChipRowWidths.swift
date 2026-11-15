import Foundation

/// How a row of chips shares its width: equal columns while the widest label fits one, otherwise
/// each chip its own width plus an equal share of what is left, so no label is cut short.
nonisolated enum ChipRowWidths {
  static func widths(ideal: [CGFloat], available: CGFloat, spacing: CGFloat) -> [CGFloat] {
    guard !ideal.isEmpty else { return [] }
    let count = CGFloat(ideal.count)
    let room = max(0, available - spacing * (count - 1))
    let column = room / count
    if ideal.allSatisfy({ $0 <= column }) { return ideal.map { _ in column } }
    let extra = max(0, room - ideal.reduce(0, +)) / count
    return ideal.map { $0 + extra }
  }
}
