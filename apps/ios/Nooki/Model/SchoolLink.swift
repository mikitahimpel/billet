import FeatureSchool

/// Where the school's store reaches the pair's room and the cat: the session's client once the account has a
/// partner, the room's cat once the room is on screen. The store is built with the stores, before either.
@MainActor
final class SchoolLink {
    var client: SchoolClient = .offline
    let stage = SchoolStage()
}
