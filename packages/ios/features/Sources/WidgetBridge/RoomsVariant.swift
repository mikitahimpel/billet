/// One of Nooki's two rooms: Ilya's diorama (`room`) and the City room with the big window.
public enum NookiRoom: String, CaseIterable, Sendable {
  case room
  case city
}

/// Which rooms a pair's Nooki has: the `rooms` experiment, given only to pairs formed after it
/// started. Every other pair, and any phone the server said nothing to, has both.
public enum RoomsVariant: String, CaseIterable, Sendable, RemoteChoice {
  case both
  case roomOnly
  case cityOnly

  /// The rooms Home offers, in the order of its switch. Never empty.
  public var rooms: [NookiRoom] {
    switch self {
    case .both: [.room, .city]
    case .roomOnly: [.room]
    case .cityOnly: [.city]
    }
  }

  /// Whether Home shows the Room/City switch, and the tip that explains it.
  public var hasRoomChoice: Bool { rooms.count > 1 }

  /// The room Home opens on.
  public var firstRoom: NookiRoom { rooms[0] }

  /// What the phone shows: a choice made in Labs on this phone, then the pair's variant, then both.
  public static func resolved(labs: RoomsVariant?, remote: RemoteFlags) -> RoomsVariant {
    labs ?? remote.choice(of: Experiments.rooms) ?? .both
  }
}
