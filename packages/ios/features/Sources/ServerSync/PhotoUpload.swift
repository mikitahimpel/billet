import Foundation

/// A Moments photo ready to send: a JPEG of at most 2048 px on the long side, its size, and its BlurHash.
public nonisolated struct PhotoUpload {
  public let jpeg: Data
  public let width: Int
  public let height: Int
  public let preview: String

  public init(jpeg: Data, width: Int, height: Int, preview: String) {
    self.jpeg = jpeg
    self.width = width
    self.height = height
    self.preview = preview
  }
}
