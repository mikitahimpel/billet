import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    static let honey = Color(hex: 0xF2A65E)
    static let honeyDeep = Color(hex: 0xD9784A)
    static let blushPink = Color(hex: 0xFF8FA3)
}

extension ShapeStyle where Self == LinearGradient {
    static var honeyGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xFFC27D), .honeyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
