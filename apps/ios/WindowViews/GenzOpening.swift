/// The street lamps' stutter as they come on with the room, from the old app's opening
/// (PetSceneReality's GenzOpening), which the window views read for their lamps.
enum GenzOpening {
  static func streetLamp(_ time: Double) -> Double {
    let local = (time - 0.3) / 1.1
    guard local >= 0 else { return 0 }
    switch local {
    case ..<0.12: return 0
    case ..<0.2: return 1
    case ..<0.34: return 0.1
    case ..<0.42: return 1
    case ..<0.5: return 0.3
    default: return 1
    }
  }
}
