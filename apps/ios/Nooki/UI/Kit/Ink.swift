import SwiftUI

/// Text and surface colors for the app's dark UI over the room and on its warm sheets.
enum Ink {
    static let primary = Color.white.opacity(0.96)
    static let secondary = Color.white.opacity(0.72)
    static let hairline = Color.white.opacity(0.14)
    /// Deep warm brown used on top of the light hero card.
    static let heroInk = Color(hex: 0x3A2114)
    static let sheet = Color(hex: 0x2A1A12)
    /// Card fill on the dark sheet.
    static let card = Color.white.opacity(0.08)
}
