import SwiftUI

/// The raw value is the room's name for it.
public enum Reaction: String, CaseIterable, Codable, Hashable, Sendable {
  case heart
  case stamp

  public var symbol: String {
    switch self {
    case .heart: "heart.fill"
    case .stamp: "seal.fill"
    }
  }

  public var title: String {
    switch self {
    case .heart: "Heart"
    case .stamp: "Stamp"
    }
  }

  public var tint: Swatch {
    switch self {
    case .heart: Palette.clayLit
    case .stamp: Palette.gold
    }
  }
}

/// The one already sent stays selected.
public struct ReactionBar: View {
  private let chosen: Reaction?
  private let onReact: (Reaction) -> Void

  public init(chosen: Reaction?, onReact: @escaping (Reaction) -> Void) {
    self.chosen = chosen
    self.onReact = onReact
  }

  public var body: some View {
    GlassGroup {
      HStack(spacing: Spacing.small) {
        ForEach(Reaction.allCases, id: \.self) { reaction in
          IconButton(
            reaction.symbol, label: "Send a \(reaction.title.lowercased())",
            isSelected: chosen == reaction
          ) { onReact(reaction) }
        }
      }
    }
  }
}

/// A small mark for a reaction a note has received.
public struct ReactionMark: View {
  private let reaction: Reaction

  public init(_ reaction: Reaction) {
    self.reaction = reaction
  }

  public var body: some View {
    Image(systemName: reaction.symbol)
      .font(IconStyle.font)
      .foregroundStyle(reaction.tint.color)
      .accessibilityLabel(reaction.title)
  }
}
