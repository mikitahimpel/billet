import SwiftUI

/// A small glass capsule with one segment selected, for choosing between a few views of the same screen. The
/// selected segment slides to the new one. Meant to float over a room, so it is glass; on a plain screen use a
/// native picker.
public struct GlassSegmented<Value: Hashable>: View {
  let segments: [(value: Value, title: String)]
  @Binding var selection: Value
  let identifier: String

  @Namespace private var thumb

  /// - Parameter identifier: Prefix of each segment's accessibility identifier, `"<identifier>.<title>"`.
  public init(
    _ segments: [(value: Value, title: String)], selection: Binding<Value>, identifier: String
  ) {
    self.segments = segments
    _selection = selection
    self.identifier = identifier
  }

  public var body: some View {
    HStack(spacing: 0) {
      ForEach(segments, id: \.value) { segment in
        let isSelected = segment.value == selection
        Button {
          withAnimation(.snappy(duration: 0.25)) { selection = segment.value }
        } label: {
          Text(segment.title)
            .font(.nookiCallout.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Ink.heroInk : Ink.primary)
            .padding(.horizontal, Space.l)
            .frame(minWidth: 72, minHeight: 36)
            .background {
              if isSelected {
                Capsule().fill(Color.honey).matchedGeometryEffect(id: "thumb", in: thumb)
              }
            }
            .frame(minHeight: Size.control)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(identifier).\(segment.title)")
      }
    }
    .padding(Space.xs - 2)
    .warmGlass(Capsule())
    .haptic(.selection, trigger: selection)
    .accessibilityElement(children: .contain)
  }
}

#Preview("Glass segmented") {
  @Previewable @State var room = "Room"
  GlassSegmented([("Room", "Room"), ("City", "City")], selection: $room, identifier: "roomSwitch")
    .padding(Space.gutter)
    .background(Color.honeyDeep)
}
