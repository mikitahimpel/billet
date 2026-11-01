import SwiftUI

/// A small neutral set of stroke colours. Placeholder values, not a palette decision.
public enum CanvasColor: CaseIterable, Hashable, Sendable {
  case black
  case gray
  case red
  case orange
  case green
  case blue

  /// The `#RRGGBB` form stored in a `Stroke`.
  public var hex: String {
    switch self {
    case .black: "#000000"
    case .gray: "#8E8E93"
    case .red: "#FF3B30"
    case .orange: "#FF9500"
    case .green: "#34C759"
    case .blue: "#007AFF"
    }
  }

  public var title: String {
    switch self {
    case .black: "Black"
    case .gray: "Gray"
    case .red: "Red"
    case .orange: "Orange"
    case .green: "Green"
    case .blue: "Blue"
    }
  }

  var color: Color {
    switch self {
    case .black: .black
    case .gray: .gray
    case .red: .red
    case .orange: .orange
    case .green: .green
    case .blue: .blue
    }
  }
}
