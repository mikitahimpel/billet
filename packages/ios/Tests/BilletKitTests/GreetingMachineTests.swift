import Testing

@testable import BilletKit

@Suite struct GreetingMachineTests {
  typealias Machine = GreetingMachine

  @Test func requestStartsLoadingAndFetches() {
    let (state, outputs) = Machine.transition(.idle, .requested(name: "Ada"))
    #expect(state == .loading(name: "Ada"))
    #expect(outputs == [.fetchGreeting(name: "Ada")])
  }

  @Test func greetingLoadsAndRecords() {
    let (state, outputs) = Machine.transition(.loading(name: "Ada"), .greeted("Hi"))
    #expect(state == .loaded(greeting: "Hi"))
    #expect(outputs == [.record("greeted")])
  }

  @Test func rejectionKeepsTheNameForRetry() {
    let (state, outputs) = Machine.transition(.loading(name: ""), .rejected(.emptyName))
    #expect(state == .failed(name: "", error: .emptyName))
    #expect(outputs == [.record("rejected")])
  }

  @Test func retryFetchesTheFailedName() {
    let (state, outputs) = Machine.transition(.failed(name: "Ada", error: .emptyName), .retried)
    #expect(state == .loading(name: "Ada"))
    #expect(outputs == [.fetchGreeting(name: "Ada")])
  }

  @Test(
    "Events that do not apply leave the state alone and do no work",
    arguments: [
      (Machine.State.loading(name: "Ada"), Machine.Event.requested(name: "Bo")),
      (.idle, .retried),
      (.loading(name: "Ada"), .retried),
      (.loaded(greeting: "Hi"), .retried),
      (.idle, .greeted("late")),
      (.loaded(greeting: "Hi"), .greeted("late")),
      (.failed(name: "Ada", error: .emptyName), .greeted("late")),
      (.idle, .rejected(.emptyName)),
      (.loaded(greeting: "Hi"), .rejected(.emptyName)),
      (.failed(name: "Ada", error: .emptyName), .rejected(.emptyName)),
    ]
  )
  func ignoredEvents(state: Machine.State, event: Machine.Event) {
    let (next, outputs) = Machine.transition(state, event)
    #expect(next == state)
    #expect(outputs.isEmpty)
  }
}
