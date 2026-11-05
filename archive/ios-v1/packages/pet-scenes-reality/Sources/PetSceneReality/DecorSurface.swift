/// Where a movable piece may stand in a room.
enum DecorSurface: String, CaseIterable, Sendable {
  case floor  // the room's floor
  case seat  // the window seat's cushion
  case top  // the top of a table, shelf, crate or other piece
  case wall  // hung on a wall
}
