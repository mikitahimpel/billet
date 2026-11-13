import Testing

@testable import ServerSync

@Suite struct PhotoReceivingTests {
  @Test @MainActor func aReceiveWhileOneRunsGoesOnceMoreInsteadOfAlongside() async {
    let gate = PhotoReceiving()
    var runs = 0
    var overlapping = false
    var running = false
    func body() async {
      overlapping = overlapping || running
      running = true
      runs += 1
      if runs == 1 {
        await gate.run(body)
        await gate.run(body)
      }
      running = false
    }
    await gate.run(body)
    #expect(runs == 2)
    #expect(!overlapping)
  }
}
