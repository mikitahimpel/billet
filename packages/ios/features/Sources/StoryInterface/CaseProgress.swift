import Foundation

/// Where a pair stands in one episode, folded from the two partners' marks. Pure: the same marks and the same
/// moment always give the same answer, and nothing in it expires.
public struct CaseProgress: Equatable, Sendable {
  public enum BeatState: Equatable, Sendable {
    /// Nothing to find here yet: the beat before it is not compared, or was compared today.
    case notYet
    /// There is something to look at. `partnerLooked`: the partner already has their half.
    case waiting(partnerLooked: Bool)
    /// This phone has its half; the partner may not.
    case looked(partnerLooked: Bool)
    /// Both have theirs, and the beat shows both halves and what they make.
    case compared

    /// There is something to look at and this phone has not.
    public var isWaiting: Bool {
      if case .waiting = self { true } else { false }
    }
  }

  public enum Verdict: Equatable, Sendable {
    case both
    case one
    case none
  }

  public enum Stage: Equatable, Sendable {
    /// Looking for the beat at `next`, the first not compared.
    case clues(next: Int)
    /// Every beat is compared; this phone has not named a suspect.
    case naming
    /// Named; the partner has not. Their choice stays hidden until it is in.
    case named(choice: String)
    /// Both named; the ending waits to be watched.
    case readyToTell(verdict: Verdict)
    case told(verdict: Verdict)
  }

  public let episode: Episode
  public let beats: [BeatState]
  public let stage: Stage

  /// The day, in the viewer's calendar, the next beat opens on, if it is waiting on a day to pass.
  public let opensOn: Date?

  public init(
    episode: Episode, mine: [CaseMark], partner: [CaseMark], now: Date, calendar: Calendar
  ) {
    let mine = mine.filter { $0.episode == episode.id }
    let partner = partner.filter { $0.episode == episode.id }
    func found(_ marks: [CaseMark], _ ref: String) -> CaseMark? {
      marks.first { $0.kind == .found && $0.ref == ref }
    }
    func named(_ marks: [CaseMark]) -> String? {
      marks.first { $0.kind == .named }.map(\.ref)
    }

    var states: [BeatState] = []
    var opens: Date?
    var previousBoth: Date?
    for (index, beat) in episode.beats.enumerated() {
      let mineFound = found(mine, beat.id)
      let theirs = found(partner, beat.id)
      let state: BeatState
      switch (mineFound, theirs) {
      case (.some, .some(let theirs)):
        state = .compared
        previousBoth = max(mineFound?.at ?? theirs.at, theirs.at)
      case (.some, .none):
        state = .looked(partnerLooked: false)
        previousBoth = nil
      case (.none, _):
        let open: Bool
        if index == 0 {
          open = true
        } else if case .compared = states[index - 1], let comparedAt = previousBoth {
          let nextDay = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: comparedAt))
          open = nextDay.map { now >= $0 } ?? true
          if !open, opens == nil { opens = nextDay }
        } else {
          open = false
        }
        state = open ? .waiting(partnerLooked: theirs != nil) : .notYet
        previousBoth = nil
      }
      states.append(state)
    }
    beats = states
    self.episode = episode

    let nextBeat = states.firstIndex { $0 != .compared }
    if let nextBeat {
      stage = .clues(next: nextBeat)
      opensOn = opens
      return
    }
    opensOn = nil
    guard let choice = named(mine) else {
      stage = .naming
      return
    }
    // The room withholds the partner's choice until this one is in, so what arrives is theirs to show.
    guard let theirs = named(partner) else {
      stage = .named(choice: choice)
      return
    }
    let right = [choice, theirs].filter { $0 == episode.culprit }.count
    let verdict: Verdict = right == 2 ? .both : right == 1 ? .one : .none
    stage =
      found(mine, Episode.endingRef) == nil
      ? .readyToTell(verdict: verdict) : .told(verdict: verdict)
  }

  /// True from the moment the ending has been watched: the souvenir is the pair's.
  public var isSolved: Bool {
    if case .told = stage { true } else { false }
  }
}
