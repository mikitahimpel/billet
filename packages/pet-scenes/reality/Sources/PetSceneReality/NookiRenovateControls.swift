import DesignSystem
import SwiftUI

/// The small control that opens the room for changes, and the tray of paints it opens. The tray
/// sits at the foot of the scene, clear of the walls it paints.
struct NookiRenovateControls: View {
  @Binding var isOpen: Bool
  @Binding var paint: NookiSwatch
  let onReset: () -> Void

  var body: some View {
    ZStack(alignment: .topLeading) {
      Button {
        isOpen.toggle()
      } label: {
        Image(systemName: isOpen ? "checkmark" : "paintbrush.pointed")
          .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
          .frame(width: 44, height: 44)
          .background(.thinMaterial, in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isOpen ? "Done changing the room" : "Change the room")
      if isOpen {
        tray
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      }
    }
    .padding(12)
  }

  private var tray: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 0) {
        ForEach(NookiSwatch.allCases, id: \.self) { option in
          Button {
            paint = option
          } label: {
            Circle()
              .fill(option.swatch.color)
              .frame(width: 34, height: 34)
              .overlay {
                if option == paint { Circle().strokeBorder(.white, lineWidth: 3) }
              }
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(option.name)
          .accessibilityAddTraits(option == paint ? .isSelected : [])
        }
        Spacer(minLength: 8)
        Button("Reset", action: onReset)
          .font(.footnote.weight(.semibold))
      }
      Text("Tap to paint. Hold furniture to move it.")
        .font(.footnote)
        .padding(.horizontal, 5)
    }
    .padding(8)
    .frame(maxWidth: 340, alignment: .leading)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Radius.plate))
  }
}
