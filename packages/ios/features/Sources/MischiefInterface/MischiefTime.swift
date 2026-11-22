/// A find's time as the screens say it.
public enum MischiefTime {
  /// "45 seconds", "1 min 12 s", "3 min".
  public static func spoken(seconds: Int) -> String {
    let seconds = max(seconds, 0)
    if seconds < 60 { return seconds == 1 ? "1 second" : "\(seconds) seconds" }
    let minutes = seconds / 60
    let rest = seconds % 60
    return rest == 0 ? "\(minutes) min" : "\(minutes) min \(rest) s"
  }
}
