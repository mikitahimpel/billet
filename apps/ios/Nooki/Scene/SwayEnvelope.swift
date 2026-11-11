/// How much the room turns under the sun: nothing while nothing happens, eased in when she walks or a finger is
/// down, and eased out again after `idleAfter` quiet seconds, so an idle room is a still frame.
struct SwayEnvelope: Equatable {
    static let idleAfter: Float = 4
    private static let rate: Float = 1.5

    private(set) var strength: Float = 0
    private var quiet: Float = idleAfter

    mutating func update(dt: Float, active: Bool, enabled: Bool) {
        quiet = active ? 0 : quiet + dt
        let target: Float = enabled && quiet < Self.idleAfter ? 1 : 0
        strength += (target - strength) * min(1, dt * Self.rate)
        if abs(target - strength) < 0.002 { strength = target }
    }
}

/// Answers true once every `interval` seconds of frames, for motion that need not be redone every frame.
struct Throttle: Equatable {
    let interval: Float
    private var waited: Float

    /// Fires on the first call, so a new room starts in its pose.
    init(interval: Float) {
        self.interval = interval
        waited = interval
    }

    mutating func fires(_ dt: Float) -> Bool {
        waited += dt
        guard waited >= interval else { return false }
        waited = 0
        return true
    }
}
