extension ActivityItem {
  /// This item's place in the list, as the server writes it: `at` padded to 16 digits, `~`, the
  /// id. The phone hands it back as `before` or as the read mark's `upTo`, so the newest item it
  /// shows can be marked read without another round trip.
  public var cursor: String {
    let digits = String(at)
    return String(repeating: "0", count: max(0, 16 - digits.count)) + digits + "~" + id
  }
}
