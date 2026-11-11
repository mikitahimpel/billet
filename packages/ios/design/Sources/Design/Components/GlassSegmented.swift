import SwiftUI

/// Floats over a room, inside the bar's `GlassGroup`; on a plain screen use a native picker.
public struct GlassSegmented<Value: Hashable>: View {
  static var inset: CGFloat { Space.xs }

  let segments: [(value: Value, title: String)]
  @Binding var selection: Value
  let identifier: String
  let identifiers: [Value: String]

  @Namespace private var thumb

  /// - Parameter identifier: Prefix of each segment's accessibility identifier, `"<identifier>.<title>"`.
  /// - Parameter identifiers: A segment's own identifier suffix where it must not follow a title that is reworded.
  public init(
    _ segments: [(value: Value, title: String)], selection: Binding<Value>, identifier: String,
    identifiers: [Value: String] = [:]
  ) {
    self.segments = segments
    _selection = selection
    self.identifier = identifier
    self.identifiers = identifiers
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
                  .overlay { Capsule().strokeBorder(Ink.selectionRim, lineWidth: 1) }
                  .matchedGeometryEffect(id: "thumb", in: thumb)
              }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(identifier).\(identifiers[segment.value] ?? segment.title)")
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
      [("Room", "Living room"), ("City", "Bedroom")], selection: $room, identifier: "roomSwitch",
      identifiers: ["Room": "Room", "City": "City"]
    )
    .padding(Space.gutter)
    .background(RoomBackdrop())
  }
}
