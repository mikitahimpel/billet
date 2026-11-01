import Pet
import Testing

@Suite("CatName")
struct CatNameTests {
  @Test func trimsSurroundingSpace() {
    #expect(CatName.clean("  Mochi \n") == "Mochi")
  }

  @Test func rejectsEmptyOrBlank() {
    #expect(CatName.clean("") == nil)
    #expect(CatName.clean("   ") == nil)
  }

  @Test func acceptsTheLongestNameAndNoMore() {
    #expect(CatName.clean(String(repeating: "a", count: CatName.maxLength)) != nil)
    #expect(CatName.clean(String(repeating: "a", count: CatName.maxLength + 1)) == nil)
  }

  @Test func countsScalarsLikeTheRoom() {
    #expect(CatName.clean(String(repeating: "🐈", count: CatName.maxLength)) != nil)
    // A family emoji is one character but five scalars.
    #expect(CatName.clean(String(repeating: "👨‍👩‍👧", count: 5)) == nil)
    #expect(CatName.clean(String(repeating: "👨‍👩‍👧", count: 4)) != nil)
  }

  @Test func rejectsControlCharacters() {
    #expect(CatName.clean("Mo\u{7}chi") == nil)
    #expect(CatName.clean("Mo\nchi") == nil)
  }

  @Test func theRoomsNameReplacesALocalOne() {
    var play = PairPlay(device: "me")
    #expect(play.catName == nil)
    play.named("Mochi")
    play.named("Biscuit")
    #expect(play.catName == "Biscuit")
  }
}
