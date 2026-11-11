import SwiftUI

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
