import Foundation
import ProfileInterface
import Testing

@Suite struct CoupleStoreTests {
  final class File {
    var couple: Couple?
    var saves = 0
  }

  func store(_ file: File) -> CoupleStore {
    CoupleStore(
      load: { file.couple },
      save: {
        file.couple = $0
        file.saves += 1
      },
      photoURL: { URL(filePath: "/dev/null/\($0)") })
  }

  @Test func withNothingSavedTheStarterIsSavedAtOnce() {
    let file = File()
    let couple = store(file).couple
    #expect(file.couple == couple)
    #expect(couple.partners == ["L", "M"])
  }

  @Test func adoptingKeepsTheHoldersMonogramAndSavesOnce() {
    let file = File()
    let couple = store(file)
    couple.setViewer("M")
    couple.adopt(pairID: "p", me: "u2", partner: "u1")
    couple.adopt(pairID: "p", me: "u2", partner: "u1")
    #expect(couple.couple.viewer == "M")
    #expect(couple.couple.pair == PairMembers(pairID: "p", users: ["M": "u2", "L": "u1"]))
    #expect(file.saves == 3)
  }

  @Test func theViewerIsFixedOncePaired() {
    let file = File()
    let couple = store(file)
    couple.adopt(pairID: "p", me: "u1", partner: "u2")
    couple.setViewer("M")
    #expect(couple.couple.viewer == "L")
    couple.leavePair()
    couple.setViewer("M")
    #expect(couple.couple.viewer == "M")
  }

  @Test func namesAreTrimmed() {
    let file = File()
    let couple = store(file)
    couple.update(names: ["L": "  Lu "], togetherSince: .distantPast)
    #expect(couple.name(of: "L") == "Lu")
    #expect(couple.initial(of: "M") == "M")
    #expect(file.couple?.togetherSince == .distantPast)
  }
}
