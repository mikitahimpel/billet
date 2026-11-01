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
    List {
      Section {
        ForEach(scenes, id: \.id) { scene in
          Button {
            selectedSceneID = scene.id
            onChoose()
          } label: {
            HStack {
              Text(scene.title)
              Spacer()
              if scene.id == selectedSceneID {
                Image(systemName: "checkmark")
                  .accessibilityLabel("Selected")
              }
            }
          }
          .tint(.primary)
        }
      } footer: {
        Text(credits)
      }
    }
    .navigationTitle("Scene")
  }

  private var credits: String {
    scenes.compactMap(\.credit).joined(separator: "\n")
  }
}
