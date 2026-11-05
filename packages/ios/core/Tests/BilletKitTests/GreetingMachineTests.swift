import Testing

@testable import BilletKit

@Suite struct GreetingMachineTests {
  typealias Machine = GreetingMachine

  @Test func requestStartsLoadingAndFetches() {
    let (state, outputs) = Machine.transition(.idle, .requested(name: "Ada"))
    #expect(state == .loading(name: "Ada", request: 1))
    #expect(outputs == [.fetchGreeting(name: "Ada", request: 1)])
  }

  @Test func greetingLoadsAndRecords() {
    let (state, outputs) = Machine.transition(
      .loading(name: "Ada", request: 1), .greeted("Hi", request: 1))
    #expect(state == .loaded(greeting: "Hi", request: 1))
    #expect(outputs == [.record("greeted")])
  }

  @Test func rejectionKeepsTheNameForRetry() {
    let (state, outputs) = Machine.transition(
      .loading(name: "", request: 1), .rejected(.emptyName, request: 1))
    #expect(state == .failed(name: "", error: .emptyName, request: 1))
    #expect(outputs == [.record("rejected")])
  }

  @Test func retryFetchesTheFailedNameAsANewRequest() {
    let (state, outputs) = Machine.transition(
      .failed(name: "Ada", error: .emptyName, request: 1), .retried)
    #expect(state == .loading(name: "Ada", request: 2))
    #expect(outputs == [.fetchGreeting(name: "Ada", request: 2)])
  }

  @Test func askingAgainAfterAGreetingFetchesAsANewRequest() {
    let (state, outputs) = Machine.transition(
      .loaded(greeting: "Hi", request: 3), .requested(name: "Bo"))
    #expect(state == .loading(name: "Bo", request: 4))
    #expect(outputs == [.fetchGreeting(name: "Bo", request: 4)])
  }

  @Test func askingAgainAfterAFailureFetchesAsANewRequest() {
    let (state, outputs) = Machine.transition(
      .failed(name: "Ada", error: .emptyName, request: 2), .requested(name: "Bo"))
    #expect(state == .loading(name: "Bo", request: 3))
    #expect(outputs == [.fetchGreeting(name: "Bo", request: 3)])
  }

  @Test func aLateResultForAnEarlierRequestChangesNothing() {
    let loading = Machine.State.loading(name: "Bo", request: 2)
    for event in [Machine.Event.greeted("Hi Ada", request: 1), .rejected(.emptyName, request: 1)] {
      let (next, outputs) = Machine.transition(loading, event)
      #expect(next == loading)
      #expect(outputs.isEmpty)
    }
  }

  @Test func aLateResultForAnEarlierRequestDoesNotOverwriteAFinishedOne() {
    let loaded = Machine.State.loaded(greeting: "Hi Bo", request: 2)
    let (next, outputs) = Machine.transition(loaded, .greeted("Hi Ada", request: 1))
    #expect(next == loaded)
    #expect(outputs.isEmpty)
  }

  @Test(
    "Events that do not apply leave the state alone and do no work",
    arguments: [
      (Machine.State.loading(name: "Ada", request: 1), Machine.Event.requested(name: "Bo")),
      (.idle, .retried),
      (.loading(name: "Ada", request: 1), .retried),
      (.loaded(greeting: "Hi", request: 1), .retried),
      (.idle, .greeted("late", request: 0)),
      (.loaded(greeting: "Hi", request: 1), .greeted("late", request: 1)),
      (.failed(name: "Ada", error: .emptyName, request: 1), .greeted("late", request: 1)),
      (.idle, .rejected(.emptyName, request: 0)),
      (.loaded(greeting: "Hi", request: 1), .rejected(.emptyName, request: 1)),
      (.failed(name: "Ada", error: .emptyName, request: 1), .rejected(.emptyName, request: 1)),
    ]
  )
  func ignoredEvents(state: Machine.State, event: Machine.Event) {
    let (next, outputs) = Machine.transition(state, event)
    #expect(next == state)
    #expect(outputs.isEmpty)
  }
}
