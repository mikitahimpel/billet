import BilletKit
import Observation
import Transport
import Wire

/// The couple's reactions to each other's photos for the signed-in `viewer`, kept in step with
/// the server. `save` keeps what the server confirmed across launches.
@MainActor
@Observable
public final class ReactionsModel {
  private let store: Store<ReactionsMachine>

  public var state: ReactionsMachine.State { store.state }

  public init(
    api: APIClient, viewer: UserId, saved: ReactionsMachine.Saved,
    save: @escaping @Sendable (ReactionsMachine.Saved) -> Void
  ) {
    store = Store<ReactionsMachine>(initial: .init(viewer: viewer, saved: saved)) { output in
      await ReactionsMachine.run(output, api: api, save: save)
    }
  }

  /// This user's reaction to the partner's photo `note`.
  public func mine(_ note: String) -> PhotoReaction? { state.mine(note) }
  /// The partner's reaction to this user's photo `note`.
  public func theirs(_ note: String) -> PhotoReaction? { state.saved.theirs[note] }
  public var lastRev: Int { state.saved.lastRev }

  public func tap(_ reaction: PhotoReaction, on note: NoteId) {
    store.send(.tapped(note: note, reaction))
  }
  public func received(_ change: NoteReaction) { store.send(.received(change)) }
  public func refresh() { store.send(.refreshed) }
  public func settled() async { await store.settled() }
}
