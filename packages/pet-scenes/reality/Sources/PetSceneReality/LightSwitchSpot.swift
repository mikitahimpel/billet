import Pet
import SwiftUI

/// The light switch on the wall as VoiceOver finds it: an element over the plate that reads
/// "Light switch, on" or "off" and presses it. Touches pass through to the room, which takes the
/// tap itself over an area wider than the plate.
struct LightSwitchSpot: View {
  let screen: GenzRoomScreen
  let press: () -> Void

  var body: some View {
    if let point = screen.lightSwitch {
      Color.clear
        .frame(width: 44, height: 56)
        .contentShape(Rectangle())
        .position(point)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Light switch")
        .accessibilityValue(GenzLightSwitch.spoken(screen.roomLight))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { press() }
    }
  }
}
