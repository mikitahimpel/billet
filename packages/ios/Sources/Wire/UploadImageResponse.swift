public struct UploadImageResponse: Codable, Hashable, Sendable {
  public let image: MediaKey

  public init(image: MediaKey) {
    self.image = image
  }
}
