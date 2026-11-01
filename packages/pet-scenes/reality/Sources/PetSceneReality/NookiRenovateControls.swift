import DesignSystem
import SwiftUI

/// The small control that opens the room for changes, and the tray of paints it opens.
struct NookiRenovateControls: View {
  @Binding var isOpen: Bool
  @Binding var paint: NookiSwatch
  let onReset: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Button {
        isOpen.toggle()
      } label: {
        Image(systemName: isOpen ? "checkmark" : "paintbrush.pointed")
          .frame(width: 44, height: 44)
          .background(.thinMaterial, in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isOpen ? "Done changing the room" : "Change the room")
      if isOpen { tray }
    }
    .padding(12)
  }

  private var tray: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
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
      }
      HStack {
        Text("Tap a wall or the floor to paint. Hold furniture to move it.")
          .font(.footnote)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        Button("Reset", action: onReset)
          .font(.footnote.weight(.semibold))
      }
    }
    .padding(10)
    .frame(maxWidth: 320, alignment: .leading)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Radius.plate))
  }
}
