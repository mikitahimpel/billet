import Foundation
import Testing

@testable import DecorInterface

@Suite struct DecorAnchorTests {
  private let seat = "base-windowseat"

  private func floor(_ id: String, _ u: Int, _ v: Int) -> Placement {
    Placement(item: id, surface: .floor, u: u, v: v)
  }

  /// Where the scene draws a piece: its cell and the flush shift.
  private func drawn(_ id: String, in layout: DecorLayout) -> (x: Double, z: Double)? {
    guard let placement = layout.placement(of: id) else { return nil }
    let shift = layout.flushShift(of: placement)
    return (DecorGrid.metres(placement.u) + shift.dx, DecorGrid.metres(placement.v) + shift.dz)
  }

  @Test func onlyTheWindowSeatIsAnchored() {
    #expect(DecorItem.item(shopID: seat)?.isAnchored == true)
    #expect(DecorItem.all.filter(\.isAnchored).map(\.id) == [seat])
  }

  @Test func aPiecePutAgainstTheSeatLeavesItWhereItIsDrawn() throws {
    // Moved and put back, the seat stands at -7: the yarn's edge is 1.4 cm short of the seat's at v -5.
    let home = try #require(DecorLayout().placement(of: seat))
    let back = DecorLayout().putting(home.moved(to: .floor, u: -7, v: 0))
    for layout in [DecorLayout(), back] {
      let before = try #require(drawn(seat, in: layout))
      for (u, v) in [(-7, -5), (-8, -5), (-7, 5), (-5, 0), (-4, 0)] {
        let yarn = floor("yarn", u, v)
        guard layout.verdict(yarn) == .fits else { continue }
        let after = try #require(drawn(seat, in: layout.putting(yarn)))
        #expect(after.x == before.x && after.z == before.z, "yarn at \(u),\(v)")
      }
    }
  }

  @Test func aDropOnTheSeatNeverSwapsOrNudgesIt() throws {
    let layout = DecorLayout().putting(floor("yarn", -2, 6))
    let home = try #require(layout.placement(of: seat))
    for v in -4...4 {
      for u in -9 ... -5 {
        let drop = layout.dropping(floor("yarn", u, v))
        switch drop {
        case .fits(let next), .slid(let next, _):
          #expect(next.placement(of: seat) == home, "yarn at \(u),\(v)")
        case .swapped(_, let other), .nudged(_, let other, _):
          #expect(other != seat, "yarn at \(u),\(v)")
        case .rejected:
          break
        }
      }
    }
  }
}
