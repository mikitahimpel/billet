import SwiftUI

/// A capsule track with one segment selected, for choosing between a few views of the same screen. The thumb is a
/// solid `Ink.surface` capsule with `Ink.text`; the unselected labels are `Ink.glassGlyphSecondary` on the track.
/// Thumb and track are both capsules with one inset, so the thumb's radius is the track's minus the inset. Meant
/// to float over a room; on a plain screen use a native picker.
public struct GlassSegmented<Value: Hashable>: View {
  static var inset: CGFloat { Space.xs }

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
            .foregroundStyle(isSelected ? Ink.text : Ink.glassGlyphSecondary)
            .padding(.horizontal, Space.l)
            .frame(minWidth: 72, minHeight: Size.control - 2 * Self.inset)
            .background {
              if isSelected {
                Capsule().fill(Ink.surface)
                  .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                  .matchedGeometryEffect(id: "thumb", in: thumb)
              }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(identifier).\(segment.title)")
      }
    }
    .padding(Self.inset)
    .background(Ink.glassFill, in: .capsule)
    .overlay(Capsule().strokeBorder(Ink.separator, lineWidth: 0.5))
    .haptic(.selection, trigger: selection)
    .accessibilityElement(children: .contain)
  }
}

#Preview("Glass segmented") {
  @Previewable @State var room = "Room"
  BothSchemes {
    GlassSegmented(
      [("Room", "Room"), ("City", "City")], selection: $room, identifier: "roomSwitch"
    )
    .padding(Space.gutter)
    .background(RoomBackdrop())
  }
}
