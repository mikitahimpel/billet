import DesignSystem
import SwiftUI

/// Pick the colour of your lamp, and see the colour of your partner's window. No labels: a colour
/// means what the two of you say it means.
public struct LampColourSection: View {
  private let store: LampStore

  public init(store: LampStore) {
    self.store = store
  }

  public var body: some View {
    HStack(alignment: .center, spacing: Spacing.medium) {
      VStack(alignment: .leading, spacing: Spacing.small) {
        Text("Your lamp")
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
        HStack(spacing: Spacing.small) {
          ForEach(LampColour.allCases, id: \.self) { colour in
            Button {
              store.choose(colour)
            } label: {
              Circle()
                .fill(colour.swatch.color)
                .frame(width: 28, height: 28)
                .overlay {
                  Circle().strokeBorder(
                    Palette.paper.color, lineWidth: store.mine == colour ? 3 : 0)
                }
                .frame(width: Target.minimum, height: Target.minimum)
                .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(colour.spokenName)
            .accessibilityAddTraits(store.mine == colour ? [.isButton, .isSelected] : .isButton)
          }
        }
      }
      Spacer(minLength: 0)
      VStack(spacing: Spacing.hair) {
        Window(colour: store.theirs?.colour)
        Text("Their window")
          .billetType(.caption)
          .foregroundStyle(Palette.muted.color)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        store.theirs.map { "Your partner's lamp is \($0.colour.spokenName)" }
          ?? "Your partner has not set a lamp")
    }
    .padding(Spacing.medium)
    .frame(maxWidth: .infinity)
    .card()
    .calmAnimation(value: store.theirs?.colour)
    .accessibilityIdentifier("lampColours")
  }

  private struct Window: View {
    let colour: LampColour?

    var body: some View {
      RoundedRectangle(cornerRadius: 6)
        .fill(Palette.pageDeep.color)
        .overlay {
          RoundedRectangle(cornerRadius: 6)
            .fill((colour?.swatch ?? Palette.muted).color.opacity(colour == nil ? 0.15 : 0.9))
            .padding(4)
        }
        .overlay { RoundedRectangle(cornerRadius: 6).stroke(Palette.wood.color, lineWidth: 2) }
        .frame(width: 44, height: 44)
        .shadow(
          color: (colour?.swatch ?? Palette.muted).color.opacity(colour == nil ? 0 : 0.6),
          radius: 10)
    }
  }
}
