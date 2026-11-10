/// One of Ourio's two rooms: the living room (`room`, the original diorama) and the bedroom (`city`, with the bed and
/// the big window). The ids are stored and reported, so they keep their first names.
public enum OurioRoom: String, CaseIterable, Sendable {
  case room
  case city
}

/// Which rooms a pair's Ourio has: the `rooms` experiment, given only to pairs formed after it
/// started. Every other pair, and any phone the server said nothing to, has both.
public enum RoomsVariant: String, CaseIterable, Sendable, RemoteChoice {
  case both
  case roomOnly
  case cityOnly

  /// The rooms Home offers, in the order of its switch. Never empty.
  public var rooms: [OurioRoom] {
    switch self {
    case .both: [.room, .city]
    case .roomOnly: [.room]
    case .cityOnly: [.city]
    }
  }

  /// Whether Home shows the living room/bedroom switch, and the tip that explains it.
  public var hasRoomChoice: Bool { rooms.count > 1 }

  /// The room Home opens on.
  public var firstRoom: OurioRoom { rooms[0] }

  /// What the phone shows: a choice made in Labs on this phone, then the pair's variant, then both.
  public static func resolved(labs: RoomsVariant?, remote: RemoteFlags) -> RoomsVariant {
    labs ?? remote.choice(of: Experiments.rooms) ?? .both
  }
}
