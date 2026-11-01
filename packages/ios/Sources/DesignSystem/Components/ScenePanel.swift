import SwiftUI

/// The big rounded frame a scene stands in.
public struct ScenePanel<Scene: View>: View {
  private let scene: Scene

  public init(@ViewBuilder scene: () -> Scene) {
    self.scene = scene()
  }

  public var body: some View {
    scene.clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
  }
}
