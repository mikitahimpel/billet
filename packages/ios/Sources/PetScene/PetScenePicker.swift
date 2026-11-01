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
        ForEach(scenes, id: \.id) { scene in
          row(scene)
        }
      }
      .litPanel(cornerRadius: Radius.control)
      if !credits.isEmpty {
        Text(credits)
          .billetType(.caption)
          .foregroundStyle(Palette.muted.color)
      }
    }
  }

  private func row(_ scene: any PetScene) -> some View {
    let selected = scene.id == selectedSceneID
    return Button {
      withAnimation(Motion.gentle) { selectedSceneID = scene.id }
      onChoose()
    } label: {
      HStack {
        Text(scene.title)
          .billetType(.body)
          .foregroundStyle(Palette.paper.color)
        Spacer(minLength: Spacing.medium)
        if selected {
          Sparkle()
            .fill(Palette.gold.color)
            .frame(width: 16, height: 16)
            .lampGlow()
            .accessibilityHidden(true)
        }
      }
      .padding(.horizontal, Spacing.medium)
      .padding(.vertical, Spacing.small)
      .frame(maxWidth: .infinity, minHeight: Target.minimum)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var credits: String {
    scenes.compactMap(\.credit).joined(separator: "\n")
  }
}
