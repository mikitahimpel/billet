import DesignSystem
import SwiftUI

/// The list of linked scenes, with the attribution their assets require.
///
/// It brings no navigation or presentation of its own, so a sheet or a settings screen can host it.
public struct PetScenePicker: View {
  private let scenes: [any PetScene]
  @Binding private var selectedSceneID: String?
  private let onChoose: () -> Void

  public init(
    scenes: [any PetScene],
    selectedSceneID: Binding<String?>,
    onChoose: @escaping () -> Void = {}
  ) {
    self.scenes = scenes
    _selectedSceneID = selectedSceneID
    self.onChoose = onChoose
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      VStack(spacing: 0) {
        ForEach(Array(scenes.enumerated()), id: \.element.id) { index, scene in
          if index > 0 {
            ListDivider()
          }
          row(scene)
        }
      }
      .card()
      if !credits.isEmpty {
        Text(credits)
          .billetType(.caption)
          .foregroundStyle(Palette.muted.color)
          .padding(.horizontal, Spacing.medium)
      }
    }
  }

  private func row(_ scene: any PetScene) -> some View {
    let selected = scene.id == selectedSceneID
    return Button {
      withAnimation(Motion.spring) { selectedSceneID = scene.id }
      onChoose()
    } label: {
      ListRow(scene.title) {
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
    .sensoryFeedback(.selection, trigger: selected)
  }

  private var credits: String {
    scenes.compactMap(\.credit).joined(separator: "\n")
  }
}
