import DesignSystem
import SwiftUI

/// The inks on the tray. Each is drawn from the world's palette and reads on paper.
public enum CanvasColor: CaseIterable, Hashable, Sendable {
  case ink
  case wood
  case clay
  case gold
  case green
  case forest

  private var swatch: Swatch {
    switch self {
    case .ink: Palette.ink
    case .wood: Palette.wood
    case .clay: Palette.clayLit
    case .gold: Palette.inkGold
    case .green: Palette.greenLit
    case .forest: Palette.green
    }
  }

  /// The `#RRGGBB` form stored in a `Stroke`.
  public var hex: String { swatch.hex }

  public var title: String {
    switch self {
    case .ink: "Ink"
    case .wood: "Wood"
    case .clay: "Clay"
    case .gold: "Gold"
    case .green: "Green"
    case .forest: "Forest"
    }
  }

  var color: Color { swatch.color }
}
