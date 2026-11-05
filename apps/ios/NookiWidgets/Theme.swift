import SwiftUI

/// The drawn room behind Mochi: scene art, not UI, so it keeps its own warm colours in either appearance. Text and
/// controls use the app's tokens (Shared/Kit), as the widgets sit beside the app on the Home Screen.
enum WidgetScene {
    /// Warm by day and blue-brown at night.
    static func room(night: Bool) -> [Color] {
        night ? [Color(hex: 0x4A3A4E), Color(hex: 0x2B2230)] : [Color(hex: 0xF7E6D4), Color(hex: 0xF0D3B4)]
    }

    static func floor(night: Bool) -> Color { night ? Color(hex: 0x5A4130) : Color(hex: 0xD9B48F) }
}

extension View {
    /// Text styles follow Dynamic Type; past this size a widget's fixed frame would cut lines off.
    func widgetTypeCap() -> some View { dynamicTypeSize(...DynamicTypeSize.xLarge) }
}

/// What the widgets are laid on, for the gallery (NookiWidgetsTests), which has no WidgetKit to draw the container
/// background.
enum WidgetGallery {
    static var background: Color { WidgetInk.background }
}
