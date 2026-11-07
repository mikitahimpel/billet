/// How the rooms' static walls, floor and furniture are made: built from boxes at launch (`live`, today's
/// rooms), or loaded as one baked, lightmapped model per room (`baked`, an experiment).
public enum RoomShell: String, CaseIterable, Sendable, RemoteChoice {
  case live
  case baked

  /// What the phone shows: a choice made in Labs on this phone, then the server's, then `live`.
  public static func resolved(labs: RoomShell?, remote: RemoteFlags) -> RoomShell {
    labs ?? remote.choice(of: Experiments.roomShell) ?? .live
  }
}
