import Foundation
import RealityKit

/// The 3D street outside the window, behind Labs' "3D view" switch.
extension GenzRoom {
  /// Shows the 3D street through the window, loading it the first time, or takes it away and
  /// leaves the flat view.
  func showStreet(_ shown: Bool) {
    guard shown else {
      streetLoad?.cancel()
      streetLoad = nil
      street?.root.removeFromParent()
      street = nil
      if screen.viewInDepth { screen.viewInDepth = false }
      return
    }
    guard street == nil, streetLoad == nil else { return }
    streetLoad = Task { [weak self] in
      guard let assets = await Street3D.assets(), !Task.isCancelled, let self else { return }
      let street = Street3D(assets: assets)
      self.street = street
      self.streetLoad = nil
      self.room.addChild(street.root)
      self.placeStreet()
      // The flat view keeps its planes until the street is there to take their place.
      self.screen.viewInDepth = true
    }
  }

  /// Fits the street to the window and turns it to the camera's home place, which moves with the
  /// shape of the view.
  func placeStreet() {
    street?.place(window: layout.window.map(\.scene), eye: camera.atHome.position)
  }
}
