import Payments
import Testing
import Transport

@testable import ServerSync

@Suite struct PaymentsServerTests {
  @Test func theServerAnswersMapToWhatTheBuyerCanDo() {
    #expect(PaymentsServer.mapped(.api(.invalidPurchase)) == .rejected)
    #expect(PaymentsServer.mapped(.api(.notFound)) == .unavailable)
    #expect(PaymentsServer.mapped(.network("offline")) == .unavailable)
  }
}
