import Foundation
import RoomInterface
import Testing

struct CatCoatTests {
  private func defaults(_ name: String) throws -> UserDefaults {
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  @Test func thePickerOffersThreeCoatsWithTheDefaultFirst() throws {
    let defaults = try defaults(#function)
    #expect(CatCoat.offered == [.grey, .ginger, .cream])
    #expect(CatCoat.offered.first == CatCoat.current(in: defaults))
  }

  @Test(arguments: [CatCoat.tuxedo, .black, .calico])
  func aSavedCoatNoLongerOfferedIsWornAsGingerAndKeptOnDisk(coat: CatCoat) throws {
    let defaults = try defaults("\(#function)-\(coat.rawValue)")
    #expect(!CatCoat.offered.contains(coat))
    defaults.set(coat.rawValue, forKey: CatCoat.key)
    #expect(CatCoat.current(in: defaults) == .ginger)
    #expect(defaults.string(forKey: CatCoat.key) == coat.rawValue)
  }

  @Test func everyCoatTheAppCanWearIsOffered() throws {
    let defaults = try defaults(#function)
    #expect(CatCoat.offered.contains(CatCoat.current(in: defaults)))
    for saved in CatCoat.allCases.map(\.rawValue) + ["", "tabby"] {
      defaults.set(saved, forKey: CatCoat.key)
      #expect(CatCoat.offered.contains(CatCoat.current(in: defaults)))
    }
    for coat in CatCoat.offered { #expect(coat.worn == coat) }
  }
}
