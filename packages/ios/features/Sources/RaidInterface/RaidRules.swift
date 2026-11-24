/// Every number of the raid in one place. Metres and seconds unless a name says ticks. They are first guesses,
/// to be tuned by playing.
public enum RaidRules {
  /// Simulation steps a second. A run is replayed from its inputs, so this never follows the display.
  public static let tickRate = 30
  public static let seconds = 45
  public static var ticks: Int { seconds * tickRate }

  /// Half the room's width.
  public static let reach = 0.49
  public static let catRadius = 0.03
  /// A piece lower than this is stepped over.
  public static let stepOver = 0.06

  public static let runSpeed = 0.2
  /// At or under this she is creeping: a squeaky board stays quiet.
  public static let creepSpeed = 0.08
  /// The finger this far ahead or more means full speed; nearer, she slows in proportion.
  public static let fullSpeedAt = 0.14
  /// A finger nearer than this is her standing still.
  public static let stillWithin = 0.012

  public static let jumpLength = 0.17
  public static let jumpTicks = 15
  public static let jumpRestTicks = 21

  public static let maxDefences = 3
  public static let sniffs = 3
  public static let sniffRadius = 0.2

  /// How near the jar she must stand, and for how long without moving, to tip it over.
  public static let pawReach = 0.065
  public static let pawTicks = 30

  public static let vacuumSpeed = 0.12
  public static let vacuumRadius = 0.05
  public static let rideTicks = 90

  public static let boxPull = 0.11
  public static let boxPullSpeed = 0.12
  public static let boxCatch = 0.035
  public static let boxTicks = 120

  public static let cucumberTrigger = 0.07
  public static let startleLeap = 0.18
  public static let startleTicks = 25

  public static let boardRadius = 0.05
  public static let lampTicks = 90
  /// How long she has to freeze after the lamp comes on.
  public static let lampGraceTicks = 9
  public static let carriedTicks = 45

  /// After a defence lets her go it leaves her alone this long.
  public static let immuneTicks = 60

  /// A defence may not sit this near where she starts, nor the jar this near.
  public static let startClear = 0.14
  public static let jarFromStart = 0.3
}
