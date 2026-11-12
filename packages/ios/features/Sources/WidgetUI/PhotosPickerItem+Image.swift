#if canImport(UIKit)
  import MomentsInterface
  import PhotosUI
  import SwiftUI
  import UIKit

  extension PhotosPickerItem {
    /// The picked photo decoded at `maxPixels` off the main thread, never as the full 12 MP bitmap.
    public func loadImage(maxPixels: Int) async -> UIImage? {
      guard let data = try? await loadTransferable(type: Data.self) else { return nil }
      return await Task.detached(priority: .userInitiated) {
        Downsample.image(data: data, maxPixels: maxPixels)
      }.value
    }
  }
#endif
