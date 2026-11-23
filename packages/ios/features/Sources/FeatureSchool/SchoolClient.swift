import Foundation
import SchoolInterface
import Transport
import Wire

/// The pair's room, as the school needs it. A failure is `nil`: the machine keeps what it had and
/// the write can be sent again.
public struct SchoolClient: Sendable {
  public var fetch: @Sendable () async -> SchoolBook?
  public var teach: @Sendable (_ trick: SchoolTrick, _ star: Int) async -> SchoolBook?
  public var send: @Sendable (RoutineTake) async -> SchoolBook?

  public init(
    fetch: @escaping @Sendable () async -> SchoolBook?,
    teach: @escaping @Sendable (SchoolTrick, Int) async -> SchoolBook?,
    send: @escaping @Sendable (RoutineTake) async -> SchoolBook?
  ) {
    self.fetch = fetch
    self.teach = teach
    self.send = send
  }

  public static let offline = SchoolClient(
    fetch: { nil }, teach: { _, _ in nil }, send: { _ in nil })

  public static func live(_ api: APIClient) -> SchoolClient {
    SchoolClient(
      fetch: { try? await api.school().book },
      teach: { trick, star in
        guard let id = TrickId(rawValue: trick.rawValue) else { return nil }
        return try? await api.teachTrick(LessonRequest(trick: id, stars: star)).book
      },
      send: { take in
        let steps = take.steps.compactMap { step in
          TrickId(rawValue: step.trick.rawValue).map {
            RoutineStep(trick: $0, landed: step.landed)
          }
        }
        guard steps.count == take.steps.count else { return nil }
        return try? await api.sendRoutine(RoutineRequest(steps: steps)).book
      })
  }
}

extension Routine {
  /// Nil when it holds a trick this build does not have: it could not be played as it went.
  var take: RoutineTake? {
    let known = steps.compactMap { step in
      SchoolTrick(rawValue: step.trick.rawValue).map {
        RoutineTake.Step(trick: $0, landed: step.landed)
      }
    }
    guard known.count == steps.count else { return nil }
    return RoutineTake(steps: known, at: Date(timeIntervalSince1970: Double(at) / 1000))
  }
}

extension SchoolResponse {
  /// A trick this build does not have is left out.
  public var book: SchoolBook {
    var skills: [SchoolTrick: TrickSkill] = [:]
    for entry in tricks {
      guard let trick = SchoolTrick(rawValue: entry.trick.rawValue) else { continue }
      skills[trick] = TrickSkill(trick: trick, stars: entry.stars, teacher: entry.by.rawValue)
    }
    return SchoolBook(skills: skills, mine: mine?.take, partner: partner?.take)
  }
}
