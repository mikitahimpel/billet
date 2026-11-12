import Design
import Pet
import SwiftUI

#if canImport(UIKit)
  /// One of she / he / they, in a row that falls back to a column where the labels don't fit.
  public struct PronounPicker: View {
    let selection: CatPronouns
    var choose: (CatPronouns) -> Void

    public init(selection: CatPronouns, choose: @escaping (CatPronouns) -> Void) {
      self.selection = selection
      self.choose = choose
    }

    public var body: some View {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: Space.s) { options }
        VStack(spacing: Space.s) { options }
      }
      .sensoryFeedback(.selection, trigger: selection)
    }

    private var options: some View {
      ForEach(CatPronouns.allCases, id: \.self) { pronouns in
        Button {
          choose(pronouns)
        } label: {
          Text(pronouns.label).lineLimit(1)
        }
        .buttonStyle(ToggleButtonStyle(isOn: selection == pronouns))
        .accessibilityIdentifier("pronouns-\(pronouns.rawValue)")
      }
    }
  }
#endif
