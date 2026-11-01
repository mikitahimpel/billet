import Testing

@testable import BilletKit

@Test func nameIsBillet() {
  #expect(BilletInfo.name == "billet")
}

@Test func throwawayFailure() {
  #expect(1 == 2)
}
