import SwiftUI

/// The ground every screen stands on. Ember dusk is the app's own; the others are a Labs switch.
/// Each keeps its middle dark enough that panels (`Palette.raised`) still lift off it and text in
/// `paper`, `paperTurned` and `muted` clears AA at its top, middle and foot (see
/// `ContrastTests`).
public enum EveningGround: String, CaseIterable, Codable, Hashable, Sendable {
  /// Deep plum falling to an ember glow, with sparks rising off it.
  case ember
  /// Wine and rose lit by candles, with a few rose-gold sparkles.
  case rose
  /// Warm cocoa with soft out-of-focus lights drifting in it.
  case cocoa
  /// The first ground: evening green to green-black with gold sparkles.
  case meadow

  public static let standard = EveningGround.ember

  public var title: String {
    switch self {
    case .ember: "Ember dusk"
    case .rose: "Candlelit rose"
    case .cocoa: "Cocoa bokeh"
    case .meadow: "Green evening"
    }
  }

  public var detail: String {
    switch self {
    case .ember: "Deep plum into an ember glow, sparks rising."
    case .rose: "Wine and rose by candlelight."
    case .cocoa: "Warm cocoa with soft lights drifting."
    case .meadow: "The original green evening."
    }
  }

  /// The sky at the top of the screen.
  public var top: Swatch {
    switch self {
    case .ember: Swatch(0x2E1838)
    case .rose: Swatch(0x3E1C2C)
    case .cocoa: Swatch(0x2C1C18)
    case .meadow: Palette.sky
    }
  }

  /// The page in the middle, where most panels stand.
  public var middle: Swatch {
    switch self {
    case .ember: Swatch(0x34172C)
    case .rose: Swatch(0x351926)
    case .cocoa: Swatch(0x24160F)
    case .meadow: Swatch(0x0C2422)
    }
  }

  /// The foot of the screen.
  public var foot: Swatch {
    switch self {
    case .ember: Swatch(0x4A1C1A)
    case .rose: Swatch(0x1E0C14)
    case .cocoa: Swatch(0x140B07)
    case .meadow: Swatch(0x081A18)
    }
  }

  /// The warm light the ground is lit by.
  public var glow: Swatch {
    switch self {
    case .ember: Swatch(0xFF7A3A)
    case .rose: Swatch(0xFFB070)
    case .cocoa: Swatch(0xFFC27A)
    case .meadow: Palette.light
    }
  }
}

extension EnvironmentValues {
  /// Which ground `EveningBackground` paints. The app sets it from Labs.
  @Entry public var eveningGround: EveningGround = .standard
}
