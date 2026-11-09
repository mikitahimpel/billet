/// `light` is drawn on light paper and `dark` on dark paper, each `#RRGGBB`.
public struct Ink: Codable, Hashable, Sendable {
  public let id: InkId
  public let name: String
  public let light: String
  public let dark: String
  public let price: Int

  public init(id: InkId, name: String, light: String, dark: String, price: Int) {
    self.id = id
    self.name = name
    self.light = light
    self.dark = dark
    self.price = price
  }
}

/// `owned` starts with the free ink.
public struct InksResponse: Codable, Hashable, Sendable {
  public let inks: [Ink]
  public let owned: [InkId]

  public init(inks: [Ink], owned: [InkId]) {
    self.inks = inks
    self.owned = owned
  }
}
