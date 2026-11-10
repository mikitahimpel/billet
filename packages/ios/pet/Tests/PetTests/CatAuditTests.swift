import Foundation
import Testing

@testable import Pet

@Suite("CatLifeAudit")
struct CatAuditTests {
  typealias Day = CatBrainTests
  static let nooki = RoomAffordances([
    RoomAffordance(id: "bed", kind: .bed), RoomAffordance(id: "tree", kind: .shelf),
    RoomAffordance(id: "sill", kind: .window), RoomAffordance(id: "ball", kind: .toy),
    RoomAffordance(id: "basket", kind: .box), RoomAffordance(id: "bowl", kind: .bowl),
  ])

  static func audit(
    seed: UInt64, room: RoomAffordances = CatAuditTests.nooki, temperament: CatTemperament? = nil
  )
    -> CatLifeAudit
  {
    CatLifeAudit(
      events: Day.bothActive, context: Day.context, seed: seed, temperament: temperament,
      room: room, start: Day.at(4), hours: 24)
  }

  @Test func printsTheAudit() {
    guard ProcessInfo.processInfo.environment["CAT_AUDIT"] != nil else { return }
    for seed in [1, 7, 42, 99, 2026] as [UInt64] {
      print(Self.audit(seed: seed).report("nooki room, seed \(seed)"))
    }
    print(Self.audit(seed: 7, room: Day.room).report("styled room, seed 7"))
    for t in CatTemperament.allCases {
      print(Self.audit(seed: 7, temperament: t).report("temperament \(t.title), seed 7"))
    }
  }
}
