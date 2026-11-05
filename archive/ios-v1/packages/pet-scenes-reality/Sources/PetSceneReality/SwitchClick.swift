import AudioToolbox

/// The click of the light switch on the room's wall: the system's short tock, which keeps to the
/// ringer switch and the system volume like the keyboard's.
enum SwitchClick {
  static func play() {
    AudioServicesPlaySystemSound(tock)
  }

  private static let tock: SystemSoundID = 1104
}
