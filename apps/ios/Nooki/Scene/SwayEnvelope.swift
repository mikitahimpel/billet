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
    var interval: Float
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

/// Passes a value only when it differs from the last one that passed, for scene writes: setting a component or a
/// transform, even to what it already holds, makes RealityKit treat the entity (and its subtree) as changed.
struct ChangeGate<Value: Equatable>: Equatable {
    private var last: Value?

    mutating func passes(_ value: Value) -> Bool {
        guard value != last else { return false }
        last = value
        return true
    }

    /// The next value passes, whatever it is.
    mutating func reopen() { last = nil }
}

/// How often the Living room's lights pulse: the full rate while she walks or a finger is down, a slow one while the
/// room is idle, so a room left alone keeps its life without dirtying its light data thirty times a second.
struct PulseRates: Equatable {
    var flame: Float
    var candle: Float
    var bulbs: Float

    static let active = PulseRates(flame: 1.0 / 30, candle: 1.0 / 15, bulbs: 0.1)
    static let idle = PulseRates(flame: 0.1, candle: 0.5, bulbs: 0.25)

    static func at(active: Bool, slowedBy slowdown: Float = 1) -> PulseRates {
        let rates = active ? PulseRates.active : .idle
        return PulseRates(flame: rates.flame * slowdown, candle: rates.candle * slowdown, bulbs: rates.bulbs * slowdown)
    }
}
