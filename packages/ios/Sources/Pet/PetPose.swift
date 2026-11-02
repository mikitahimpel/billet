/// A still picture of the pet. Surfaces that cannot run a scene engine, such as the widget, show
/// these from the App Group instead.
public enum PetPose: String, CaseIterable, Hashable, Sendable {
  case sleeping
  case proud

  /// File name in the App Group container.
  public var fileName: String { "pet-pose-\(rawValue).png" }
}
