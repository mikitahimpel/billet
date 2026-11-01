/// A drawing tool. `width` is a fraction of the canvas width, as `Stroke.width` expects.
public enum CanvasTool: CaseIterable, Hashable, Sendable {
  case pen
  case marker

  public var width: Double {
    switch self {
    case .pen: 0.006
    case .marker: 0.024
    }
  }

  public var title: String {
    switch self {
    case .pen: "Pen"
    case .marker: "Marker"
    }
  }
}
