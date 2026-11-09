import BilletKit
import Transport
import Wire

/// The couple's reactions to each other's photos. A tap shows at once; a failure puts back what was
/// there. One request per photo is out at a time; its answer sends the latest wish if it differs.
/// Changes arrive in `rev` order, and one at or below `lastRev` is already held.
public enum ReactionsMachine: Machine {
  /// What is kept across launches.
  public struct Saved: Equatable, Sendable, Codable {
    /// The highest `rev` applied, so a page or a socket asks only for what is newer.
    public var lastRev: Int
    /// This user's reaction to each of the partner's photos, by note id, as the server has it.
    public var mine: [String: PhotoReaction]
    /// The partner's reaction to each of this user's photos, by note id.
    public var theirs: [String: PhotoReaction]

    public init(
      lastRev: Int = 0, mine: [String: PhotoReaction] = [:], theirs: [String: PhotoReaction] = [:]
    ) {
      self.lastRev = lastRev
      self.mine = mine
      self.theirs = theirs
    }
  }

  public struct State: Equatable, Sendable {
    public let viewer: UserId
    public var saved: Saved
    /// Taps not confirmed yet: the reaction wanted on each photo, `nil` to take it back.
    public var wanted: [String: PhotoReaction?]
    /// Photos with a request out.
    public var sending: Set<String>
    public var loading: Bool

    public init(viewer: UserId, saved: Saved) {
      self.viewer = viewer
      self.saved = saved
      wanted = [:]
      sending = []
      loading = false
    }

    /// The reaction this user sees as theirs on `note`: the one they just tapped, else the
    /// server's.
    public func mine(_ note: String) -> PhotoReaction? {
      if let wish = wanted[note] { return wish }
      return saved.mine[note]
    }
  }

  public enum Event: Equatable, Sendable {
    /// The user tapped `reaction` on the partner's photo: the one shown takes it back.
    case tapped(note: NoteId, PhotoReaction)
    /// A change from either phone, from the socket or a page.
    case received(NoteReaction)
    /// The server holds `reaction` (`nil`: none) as this user's on `note`.
    case confirmed(note: NoteId, PhotoReaction?)
    case failed(note: NoteId)
    /// Asks for every change after `lastRev`.
    case refreshed
    case pageLoaded([NoteReaction])
    case pageFailed
  }

  public enum Output: Equatable, Sendable {
    case send(ReactRequest)
    case load(after: Int)
    case save(Saved)
  }

  /// Changes per page; a full page asks for the next.
  public static let pageSize = 100

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    var next = state
    switch event {
    case .tapped(let note, let reaction):
      let key = note.rawValue
      let wish: PhotoReaction? = state.mine(key) == reaction ? nil : reaction
      next.wanted[key] = .some(wish)
      if state.sending.contains(key) { return (next, []) }
      next.sending.insert(key)
      return (next, [.send(ReactRequest(note: note, reaction: wish))])

    case .received(let change):
      guard change.rev > state.saved.lastRev else { return (state, []) }
      next.saved = applied(change, to: state.saved, viewer: state.viewer)
      return (next, [.save(next.saved)])

    case .confirmed(let note, let reaction):
      let key = note.rawValue
      next.sending.remove(key)
      next.saved.mine[key] = reaction
      let outputs: [Output] = [.save(next.saved)]
      guard let wish = state.wanted[key] else { return (next, outputs) }
      if wish == reaction {
        next.wanted[key] = nil
        return (next, outputs)
      }
      next.sending.insert(key)
      return (next, outputs + [.send(ReactRequest(note: note, reaction: wish))])

    case .failed(let note):
      next.sending.remove(note.rawValue)
      next.wanted[note.rawValue] = nil
      return (next, [])

    case .refreshed:
      if state.loading { return (state, []) }
      next.loading = true
      return (next, [.load(after: state.saved.lastRev)])

    case .pageLoaded(let changes):
      next.saved = changes.reduce(state.saved) { saved, change in
        change.rev > saved.lastRev ? applied(change, to: saved, viewer: state.viewer) : saved
      }
      let outputs: [Output] = next.saved == state.saved ? [] : [.save(next.saved)]
      guard changes.count >= pageSize else {
        next.loading = false
        return (next, outputs)
      }
      return (next, outputs + [.load(after: next.saved.lastRev)])

    case .pageFailed:
      next.loading = false
      return (next, [])
    }
  }

  private static func applied(_ change: NoteReaction, to saved: Saved, viewer: UserId) -> Saved {
    var saved = saved
    saved.lastRev = change.rev
    if change.by == viewer {
      saved.mine[change.note.rawValue] = change.reaction
    } else {
      saved.theirs[change.note.rawValue] = change.reaction
    }
    return saved
  }
}

extension ReactionsMachine {
  public static func run(
    _ output: Output, api: APIClient, save: @Sendable (Saved) -> Void
  ) async -> Event? {
    switch output {
    case .send(let request):
      do {
        let response = try await api.react(request)
        return .confirmed(note: request.note, response.reaction.reaction)
      } catch .api(.notFound) where request.reaction == nil {
        // Nothing to take back: the server holds none.
        return .confirmed(note: request.note, nil)
      } catch {
        return .failed(note: request.note)
      }
    case .load(let after):
      guard let page = try? await api.listReactions(after) else { return .pageFailed }
      return .pageLoaded(page.reactions)
    case .save(let saved):
      save(saved)
      return nil
    }
  }
}
