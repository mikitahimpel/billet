import SwiftUI

/// A capsule track with one segment selected, for choosing between a few views of the same screen. The track is
/// the `bar` glass; the thumb is `Ink.glassSelection` under an `Ink.glassGlyph` label, as the tab bar's, and the
/// unselected labels are `Ink.glassGlyphSecondary`. Thumb and track are both capsules with one inset, so the
/// thumb's radius is the track's minus the inset. Meant to float over a room, inside the bar's `GlassGroup`; on
/// a plain screen use a native picker.
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
            .font(.ourioCallout.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Ink.glassGlyph : Ink.glassGlyphSecondary)
            .padding(.horizontal, Space.l)
            .frame(minWidth: 72, minHeight: Size.control - 2 * Self.inset)
            .background {
              if isSelected {
                Capsule().fill(Ink.glassSelection)
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
    .glass(.capsule, role: .bar)
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
