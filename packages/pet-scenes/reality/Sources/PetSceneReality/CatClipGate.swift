import Pet

/// Stands between the clip the room asks for each frame and the one the rig plays, so the cat
/// never twitches: the steps, one-shots, reflexes and trips the room composes can ask for a new
/// clip for a frame or two (a walk of a few centimetres on arrival, a one-shot cut short by the
/// next step), and each switch starts a cross-fade from wherever the body is.
///
/// A new clip plays once it has been asked for steadily for ``debounce``, and only after the one
/// playing has had ``minimumDwell``. Setting off or stopping (into or out of a walk, run or carry)
/// waits only for the debounce, so the cat never slides along in a sitting pose. A forced switch,
/// such as being picked up, plays at once.
struct CatClipGate {
  /// How long a newly asked-for clip must stay asked for before it plays, in seconds.
  static let debounce = 0.12
  /// The least a clip plays before another may take over, in seconds.
  static let minimumDwell = 0.5

  private(set) var shown: CatAction?
  private var shownSince = 0.0
  private var wanted: CatAction?
  private var wantedSince = 0.0

  /// Whether `action` moves the cat along, so starting or stopping it must not wait long.
  static func travels(_ action: CatAction) -> Bool {
    action == .walk || action == .run || action == .carry
  }

  /// The clip to play at `clock`, for the room asking for `wish`.
  mutating func choose(_ wish: CatAction, at clock: Double, force: Bool = false) -> CatAction {
    guard let current = shown else { return show(wish, at: clock) }
    if wish == current {
      wanted = nil
      return current
    }
    if wish != wanted {
      wanted = wish
      wantedSince = clock
    }
    if force { return show(wish, at: clock) }
    let steady = clock - wantedSince >= Self.debounce - 1e-9
    let settled =
      Self.travels(wish) || Self.travels(current)
      || clock - shownSince >= Self.minimumDwell - 1e-9
    return steady && settled ? show(wish, at: clock) : current
  }

  private mutating func show(_ action: CatAction, at clock: Double) -> CatAction {
    shown = action
    shownSince = clock
    wanted = nil
    return action
  }
}
