import Foundation
import Synchronization
import Testing
import Transport
import Wire

@testable import FeatureInbox

private func item(
  _ event: ActivityEvent = .catPetted, _ actor: ActivityActor = .partner, id: String = "x",
  at: Int = 0
) -> ActivityItem {
  let digits = String(at)
  let cursor = String(repeating: "0", count: max(0, 16 - digits.count)) + digits + "~" + id
  return ActivityItem(id: id, at: at, actor: actor, event: event, target: nil, cursor: cursor)
}

@Suite struct InboxMachineTests {
  typealias M = InboxMachine

  static let a = item(id: "a", at: 3)
  static let b = item(.catSlept, .cat, id: "b", at: 2)
  static let c = item(.catFed(grams: 1), .me, id: "c", at: 1)

  static func loaded(_ items: [ActivityItem], next: String? = nil, request: Int = 1) -> M.State {
    var state = M.State.initial
    state.request = request
    state.sheet = .loaded(M.Page(items: items, next: next, head: items.first?.cursor))
    return state
  }

  @Test func openingLoadsTheFirstPageAndMarksItRead() {
    var (state, outputs) = M.transition(.initial, .opened)
    #expect(state.sheet == .loading)
    #expect(outputs == [.loadFirst(request: 1)])

    let page = ActivityResponse(items: [Self.a, Self.b, Self.c], next: "older", unread: 1)
    (state, outputs) = M.transition(state, .loaded(page, request: 1))
    #expect(state.unread == 1)
    #expect(state.sheet.page?.fresh == ["a"])
    #expect(state.sheet.page?.next == "older")
    #expect(outputs == [.markRead(upTo: Self.a.cursor)])

    (state, outputs) = M.transition(state, .counted(0))
    #expect(state.unread == 0)
    #expect(state.sheet.page?.fresh == ["a"], "new rows stay marked until the next open")
    #expect(outputs.isEmpty)
  }

  @Test func theServersHeadIsTheReadMark() {
    let (state, _) = M.transition(.initial, .opened)
    let page = ActivityResponse(items: [Self.a], head: "head-cursor", unread: 2)
    let (_, outputs) = M.transition(state, .loaded(page, request: 1))
    #expect(outputs == [.markRead(upTo: "head-cursor")])
  }

  @Test func nothingUnreadSendsNoReadMark() {
    let (state, _) = M.transition(.initial, .opened)
    let (_, outputs) = M.transition(
      state, .loaded(ActivityResponse(items: [Self.a], unread: 0), request: 1))
    #expect(outputs.isEmpty)
  }

  @Test func openingAgainKeepsTheListShowing() {
    let shown = Self.loaded([Self.a])
    let (state, outputs) = M.transition(shown, .opened)
    #expect(state.sheet == .refreshing(shown.sheet.page!))
    #expect(outputs == [.loadFirst(request: 2)])
  }

  @Test func anEmptyListLoadsAsNew() {
    let (state, _) = M.transition(Self.loaded([]), .opened)
    #expect(state.sheet == .loading)
  }

  @Test func withoutAPartnerTheInboxSaysSo() {
    let (state, _) = M.transition(Self.loaded([Self.a]), .opened)
    let (failed, _) = M.transition(state, .loadFailed(.unpaired, request: 2))
    #expect(failed.sheet == .unpaired)
    #expect(M.Failure(.api(.notFound)) == .unpaired)
    #expect(M.Failure(.network("x")) == .unavailable)
  }

  @Test func aFailedRefreshKeepsTheOldList() {
    let shown = Self.loaded([Self.a])
    let (state, _) = M.transition(shown, .opened)
    let (failed, _) = M.transition(state, .loadFailed(.unavailable, request: 2))
    #expect(failed.sheet == .stale(shown.sheet.page!))
  }

  @Test func aFailedFirstLoadHasNothingToShow() {
    let (state, _) = M.transition(.initial, .opened)
    let (failed, _) = M.transition(state, .loadFailed(.unavailable, request: 1))
    #expect(failed.sheet == .failed)
  }

  @Test func anEarlierOpensAnswerIsIgnored() {
    var (state, _) = M.transition(.initial, .opened)
    (state, _) = M.transition(state, .loadFailed(.unavailable, request: 1))
    (state, _) = M.transition(state, .opened)
    let late = ActivityResponse(items: [Self.a], unread: 1)
    let (after, outputs) = M.transition(state, .loaded(late, request: 1))
    #expect(after == state)
    #expect(outputs.isEmpty)
    #expect(M.transition(state, .loadFailed(.unpaired, request: 1)).0 == state)
  }

  static let loading = M.transition(.initial, .opened).0
  static let refreshing = M.transition(loaded([a]), .opened).0

  @Test(arguments: [loading, refreshing])
  func openingWhileTheFirstPageLoadsWaitsForIt(state: M.State) {
    let (after, outputs) = M.transition(state, .opened)
    #expect(after == state)
    #expect(outputs.isEmpty)
    let page = ActivityResponse(items: [Self.b], unread: 0)
    #expect(
      M.transition(after, .loaded(page, request: state.request)).0.sheet.page?.items == [Self.b])
  }

  static func sheet(_ sheet: M.Sheet) -> M.State {
    var state = M.State.initial
    state.sheet = sheet
    return state
  }

  @Test(arguments: [
    sheet(.idle), sheet(.unpaired), sheet(.failed), sheet(.loaded(M.Page(items: [a]))),
    sheet(.stale(M.Page(items: [a]))),
  ])
  func openingFromARestingSheetLoadsAgain(state: M.State) {
    let (after, outputs) = M.transition(state, .opened)
    #expect(after.sheet.isLoadingFirst)
    #expect(outputs == [.loadFirst(request: state.request + 1)])
  }

  @Test func pagesWithoutALoadAreIgnored() {
    let shown = Self.loaded([Self.a])
    let page = ActivityResponse(items: [Self.b], unread: 0)
    #expect(M.transition(shown, .loaded(page, request: 1)).0 == shown)
    #expect(M.transition(.initial, .loadFailed(.unavailable, request: 0)).0 == .initial)
  }

  @Test func theEndLoadsTheOlderPageOnce() {
    var (state, outputs) = M.transition(Self.loaded([Self.a], next: "older"), .reachedEnd)
    #expect(outputs == [.loadMore(after: "older")])
    (state, outputs) = M.transition(state, .reachedEnd)
    #expect(outputs.isEmpty, "the row appearing again while the page loads asks for nothing")

    let older = ActivityResponse(items: [Self.a, Self.b], next: nil, unread: 0)
    (state, _) = M.transition(state, .loadedMore(older, after: "older"))
    #expect(state.sheet.page?.items.map(\.id) == ["a", "b"])
    #expect(state.sheet.page?.next == nil)
    (state, outputs) = M.transition(state, .reachedEnd)
    #expect(outputs.isEmpty, "the last page has no older one")
  }

  @Test func aFailedOlderPageCanBeAskedForAgain() {
    var (state, _) = M.transition(Self.loaded([Self.a], next: "older"), .reachedEnd)
    (state, _) = M.transition(state, .loadMoreFailed(after: "older"))
    #expect(M.transition(state, .reachedEnd).1 == [.loadMore(after: "older")])
  }

  @Test func anOlderPageAfterARefreshIsIgnored() {
    var (state, _) = M.transition(Self.loaded([Self.a], next: "older"), .reachedEnd)
    (state, _) = M.transition(state, .opened)
    let older = ActivityResponse(items: [Self.b], unread: 0)
    #expect(M.transition(state, .loadedMore(older, after: "older")).0 == state)
    #expect(M.transition(state, .loadMoreFailed(after: "older")).0 == state)
  }

  @Test(arguments: [M.State.initial, loaded([a]), loaded([a], next: "older")])
  func theEndOnlyLoadsFromALoadedList(state: M.State) {
    let refreshing = M.transition(state, .opened).0
    #expect(M.transition(refreshing, .reachedEnd).1.isEmpty)
  }

  @Test func theBadgeCountsInAnyState() {
    let (state, outputs) = M.transition(.initial, .countRequested)
    #expect(outputs == [.count])
    #expect(M.transition(state, .counted(4)).0.unread == 4)
  }

  @Test func theNewestOthersItemsAreTheUnreadOnes() {
    let items = [
      item(.catFed(grams: 1), .me, id: "a"), item(.catPetted, id: "b"),
      item(.catSlept, .cat, id: "c"), item(.catPlayed, id: "d"),
    ]
    #expect(M.unreadIDs(in: items, count: 2) == ["b", "c"])
    #expect(M.unreadIDs(in: items, count: 0).isEmpty)
  }
}

@MainActor @Suite struct InboxModelTests {
  @Test func openingMarksReadUpToTheNewestItem() async {
    let marked = Mutex<[String]>([])
    let newest = item(id: "cat:1", at: 1_700_000_101_000)
    let model = InboxModel(
      list: { (_) async throws(TransportError) in
        ActivityResponse(items: [newest, item(.catPlayed, id: "cat:0", at: 1)], unread: 1)
      },
      markRead: { (request) async throws(TransportError) in
        marked.withLock { $0.append(request.upTo) }
        return ActivityUnreadResponse(unread: 0)
      })
    await model.open()
    #expect(model.sheet.page?.fresh == ["cat:1"])
    #expect(model.unread == 0)
    #expect(marked.withLock { $0 } == ["0001700000101000~cat:1"])
  }

  @Test func aFirstPageThatNeverComesEndsInFailed() async {
    let model = InboxModel(
      list: { (_) async throws(TransportError) in
        try? await Task.sleep(for: .seconds(600))
        return ActivityResponse(items: [], unread: 0)
      },
      markRead: { (_) async throws(TransportError) in ActivityUnreadResponse(unread: 0) },
      timeout: .milliseconds(50))
    await model.open()
    #expect(model.sheet == .failed)
  }

  @Test func aRefreshThatNeverComesKeepsTheList() async {
    let calls = Mutex(0)
    let shown = item(id: "cat:1", at: 1)
    let model = InboxModel(
      list: { (_) async throws(TransportError) in
        if calls.withLock({
          $0 += 1
          return $0
        }) > 1 {
          try? await Task.sleep(for: .seconds(600))
        }
        return ActivityResponse(items: [shown], unread: 0)
      },
      markRead: { (_) async throws(TransportError) in ActivityUnreadResponse(unread: 0) },
      timeout: .milliseconds(50))
    await model.open()
    await model.open()
    #expect(model.sheet == .stale(InboxMachine.Page(items: [shown], head: shown.cursor)))
  }

  @Test func theBadgeRefreshesWithoutOpening() async {
    let model = InboxModel(
      list: { (_) async throws(TransportError) in ActivityResponse(items: [], unread: 3) },
      markRead: { (_) async throws(TransportError) in ActivityUnreadResponse(unread: 0) })
    await model.refreshCount()
    #expect(model.unread == 3)
    #expect(model.sheet == .idle)
  }
}

@Suite struct InboxDayTests {
  @Test func itemsAreGroupedByDayWithTodayAndYesterday() {
    // 08:00 UTC: two items fall on that day, one on the day before.
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let ms = { (minutesAgo: Double) in Int((now.timeIntervalSince1970 - minutesAgo * 60) * 1000) }
    let items = [
      item(id: "a", at: ms(4)), item(id: "b", at: ms(70)), item(id: "c", at: ms(60 * 20)),
    ]
    let days = InboxDay.group(items, now: now, calendar: utc)
    #expect(days.map(\.title) == ["Today", "Yesterday"])
    #expect(days.map(\.items.count) == [2, 1])
  }
}
