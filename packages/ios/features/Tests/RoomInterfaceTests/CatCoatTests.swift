import Foundation
import RoomInterface
import Testing

struct CatCoatTests {
  @Test func thePickerOffersFourCoatsWithTheDefaultFirst() throws {
    let defaults = try #require(UserDefaults(suiteName: #function))
    defaults.removePersistentDomain(forName: #function)
    #expect(CatCoat.offered == [.grey, .ginger, .cream, .black])
    #expect(CatCoat.offered.first == CatCoat.current(in: defaults))
  }

  @Test func aCoatNoLongerOfferedStillLoads() throws {
    let defaults = try #require(UserDefaults(suiteName: #function))
    defer { defaults.removePersistentDomain(forName: #function) }
    for coat in [CatCoat.tuxedo, .calico] {
      #expect(!CatCoat.offered.contains(coat))
      defaults.set(coat.rawValue, forKey: CatCoat.key)
      #expect(CatCoat.current(in: defaults) == coat)
    }
  }
}
