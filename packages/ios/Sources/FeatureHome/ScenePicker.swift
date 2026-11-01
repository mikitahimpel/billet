import PetScene
import SwiftUI

/// The list of linked scenes, with the attribution their assets require.
struct ScenePicker: View {
  let scenes: [any PetScene]
  @Binding var selectedSceneID: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(scenes, id: \.id) { scene in
            Button {
              selectedSceneID = scene.id
              dismiss()
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
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
    }
    .presentationDetents([.medium])
  }

  private var credits: String {
    scenes.compactMap(\.credit).joined(separator: "\n")
  }
}
