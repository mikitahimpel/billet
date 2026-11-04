import DesignSystem
import Pet
import SwiftUI
import WidgetBridge

/// Which cat lives in the room, one row per model with a check on the chosen one, and the coats
/// the chosen one can wear. Saved with the Labs flags; the room swaps cats without a restart.
struct CatPicker: View {
  let model: WidgetFeaturesModel
  let cats: [CatModel]

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text("Cat")
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
        .padding(.horizontal, Spacing.medium)
      SettingsGroup {
        ForEach(cats, id: \.self) { cat in
          if cat != cats.first { ListDivider() }
          row(cat)
          if model.cat.model == cat, cat.coats.count > 1 {
            coats(for: cat)
          }
        }
      }
    }
  }

  private func row(_ cat: CatModel) -> some View {
    let selected = model.cat.model == cat
    return Button {
      withAnimation(Motion.spring) { model.setCat(CatChoice(model: cat, coat: model.cat.coat)) }
    } label: {
      ListRow(cat.title, subtitle: cat.detail) {
        EmptyView()
      } trailing: {
        if selected {
          RowIcon("checkmark", color: Palette.gold)
            .transition(.opacity)
        }
      }
    }
    .buttonStyle(RowButtonStyle())
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("cat-\(cat.rawValue)")
    .sensoryFeedback(.selection, trigger: selected)
  }

  private func coats(for cat: CatModel) -> some View {
    HStack(spacing: Spacing.small) {
      ForEach(cat.coats, id: \.self) { coat in
        let selected = model.cat.coat == coat
        Button {
          withAnimation(Motion.spring) { model.setCat(CatChoice(model: cat, coat: coat)) }
        } label: {
          Circle()
            .fill(Self.swatch(coat))
            .frame(width: 30, height: 30)
            .overlay(Circle().strokeBorder(Palette.ink.color.opacity(0.15), lineWidth: 1))
            .padding(3)
            .overlay(
              Circle().strokeBorder(Palette.gold.color, lineWidth: selected ? 2 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(coat.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("coat-\(coat.rawValue)")
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.bottom, Spacing.small)
  }

  /// A two-tone dot for each coat: the coat colour with its lighter belly.
  static func swatch(_ coat: CatCoat) -> LinearGradient {
    let (top, bottom): (Color, Color) =
      switch coat {
      case .natural:
        (Color(red: 0.93, green: 0.58, blue: 0.27), Color(red: 0.36, green: 0.36, blue: 0.4))
      case .greyWhite:
        (Color(red: 0.55, green: 0.56, blue: 0.6), Color(red: 0.97, green: 0.97, blue: 0.96))
      case .black:
        (Color(red: 0.14, green: 0.13, blue: 0.15), Color(red: 0.3, green: 0.29, blue: 0.32))
      }
    return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
  }
}
