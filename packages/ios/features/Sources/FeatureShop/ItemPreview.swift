import SwiftUI

/// The 3D turntable of a piece in the item sheet. It draws with RealityKit, which a package may not
/// import, so the app makes it (`ShopHost.makeItemPreview`).
public protocol ItemPreview: AnyObject {
  /// True once the scene has drawn a few frames with the model loaded (hidden), so the still can give way to it.
  var isDrawn: Bool { get }
  /// Set as the still fades: the model fades in over it, and only starts turning once it has.
  var isRevealed: Bool { get set }
  var isDragging: Bool { get set }
  func spin(_ delta: Float)
  func celebrate()
  /// The scene, filling the stage.
  func scene(for item: ShopItem) -> AnyView
}

public enum ItemStage {
  public static let height: CGFloat = 260
  /// Vertical padding the still gets inside the stage; the camera allows for it.
  public static let thumbnailInset: CGFloat = 8
}
