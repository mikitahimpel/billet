import Wire

/// One ink colour from the shop's catalog, as the palettes show it. `price` is in coins; the free ink costs nothing.
/// Notes sit on light paper and write in `light`; the lock-screen canvas is dark and draws in `dark`.
public nonisolated struct PaletteInk: Identifiable, Hashable, Sendable {
  /// The catalog id, `ink-<name>`, also the key in the wallet's owned set.
  public let id: String
  public let name: String
  public let light: UInt32
  public let dark: UInt32
  public let price: Int

  public init(id: String, name: String, light: UInt32, dark: UInt32, price: Int) {
    self.id = id
    self.name = name
    self.light = light
    self.dark = dark
    self.price = price
  }

  /// Nil when a colour isn't `#RRGGBB`.
  public init?(_ ink: Wire.Ink) {
    guard let light = Self.parse(ink.light), let dark = Self.parse(ink.dark) else { return nil }
    self.init(id: ink.id.rawValue, name: ink.name, light: light, dark: dark, price: ink.price)
  }

  public var wireID: InkId { InkId(id) }

  public func isOwned(_ owned: Set<String>) -> Bool { price == 0 || owned.contains(id) }

  /// `#RRGGBB`, as strokes carry it.
  public static func wire(_ hex: UInt32) -> String { String(format: "#%06X", hex) }

  public static func parse(_ hex: String) -> UInt32? {
    guard hex.count == 7, hex.first == "#" else { return nil }
    return UInt32(hex.dropFirst(), radix: 16)
  }

  public static func isInk(_ id: String) -> Bool { id.hasPrefix("ink-") }

  public static let free = PaletteInk(
    id: InkId.free.rawValue, name: "Graphite", light: 0x2B2B2E, dark: 0xECEAE4, price: 0)

  /// The catalog as `packages/contracts/domain/src/inks.ts` has it, for before the server answers and for offline.
  public static let bundled: [PaletteInk] = [
    free,
    PaletteInk(id: "ink-rose", name: "Rose", light: 0xD2456B, dark: 0xFF8FAB, price: 60),
    PaletteInk(id: "ink-sea", name: "Sea", light: 0x1F6FB2, dark: 0x7CC4FF, price: 60),
    PaletteInk(id: "ink-moss", name: "Moss", light: 0x3E7D3A, dark: 0x9BD88F, price: 60),
    PaletteInk(id: "ink-ember", name: "Ember", light: 0xD9622B, dark: 0xFFA36E, price: 60),
    PaletteInk(id: "ink-plum", name: "Plum", light: 0x6B3FA0, dark: 0xC3A2F0, price: 90),
    PaletteInk(id: "ink-gold", name: "Gold", light: 0xB08A1E, dark: 0xF2CF5B, price: 120),
  ]
}
