import DesignSystem
import Labs
import Pet
import SwiftUI

extension View {
  /// Presents the cat's needs card as a short sheet, just as tall as the card, so the room stays
  /// in sight above it. An action closes it, so what the cat does about it shows.
  func needsSheet(
    isPresented: Binding<Bool>, mood: CatNeedsSnapshot?, onAnswer: @escaping (PetNeed) -> Void
  ) -> some View {
    sheet(isPresented: isPresented) {
      if let mood {
        NeedsSheet(mood: mood) { need in
          isPresented.wrappedValue = false
          onAnswer(need)
        }
      }
    }
  }
}

private struct NeedsSheet: View {
  let mood: CatNeedsSnapshot
  let onAnswer: (PetNeed) -> Void

  /// The card's height, measured, so the sheet fits it.
  @State private var height: CGFloat = 320

  var body: some View {
    CatNeedsCard(mood, onAnswer: onAnswer)
      .padding(.horizontal, Spacing.medium)
      .padding(.top, Spacing.large)
      .padding(.bottom, Spacing.small)
      .fixedSize(horizontal: false, vertical: true)
      .onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: {
        height = $0
      }
      .frame(maxHeight: .infinity, alignment: .top)
      // The app's one sheet look, but no title row: the card's first line names the cat.
      .billetSheet([.height(height)])
  }
}
