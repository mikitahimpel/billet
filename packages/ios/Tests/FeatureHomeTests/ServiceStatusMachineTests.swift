import Foundation
import Testing
import Wire

@testable import FeatureHome

@Suite struct ServiceStatusMachineTests {
  private static let resting = StatusMessage(key: "maintenance.default", text: "Resting.")
  private static let slow = StatusMessage(key: "notice.slow-notes", text: "Notes may be slow.")

  private static func status(
    maintenance: Bool = false, until: String? = nil, minVersion: String? = nil,
    notice: StatusMessage? = nil
  ) -> AppStatus {
    AppStatus(
      maintenance: MaintenanceStatus(
        active: maintenance, message: maintenance ? resting : nil, until: until),
      minVersion: minVersion.flatMap(AppVersion.init), notice: notice)
  }

  private static func state(_ version: String? = "1.2.0+14") -> ServiceStatusMachine.State {
    ServiceStatusMachine.State(appVersion: version.flatMap(AppVersion.init))
  }

  private static func receive(
    _ status: AppStatus, in state: ServiceStatusMachine.State = state()
  ) -> (ServiceStatusMachine.State, [ServiceStatusMachine.Output]) {
    ServiceStatusMachine.transition(state, .received(status))
  }

  @Test func nothingHeardIsNormal() {
    #expect(Self.state().screen == .normal(notice: nil))
  }

  @Test func maintenanceShowsItsBlock() {
    let status = Self.status(maintenance: true, until: "2026-11-03T22:30:00Z")
    let (next, outputs) = Self.receive(status)
    #expect(next.screen == .maintenance(status.maintenance))
    #expect(outputs.isEmpty)
  }

  @Test(arguments: ["1.2.0+15", "1.2+99", "1.3", "2", "1.2.1+1"])
  func aNewerMinimumRequiresAnUpdate(_ minimum: String) {
    #expect(Self.receive(Self.status(minVersion: minimum)).0.screen == .updateRequired)
  }

  @Test(arguments: ["1.2.0+14", "1.2.0+13", "1.2", "1.2.0", "1.1.9+99", "0.9"])
  func anOlderOrEqualMinimumChangesNothing(_ minimum: String) {
    #expect(Self.receive(Self.status(minVersion: minimum)).0.screen == .normal(notice: nil))
  }

  @Test func aBuildThatDoesNotKnowItsVersionIsNeverStopped() {
    let (next, _) = Self.receive(Self.status(minVersion: "99"), in: Self.state(nil))
    #expect(next.screen == .normal(notice: nil))
    let (odd, _) = Self.receive(Self.status(minVersion: "99"), in: Self.state("beta"))
    #expect(odd.screen == .normal(notice: nil))
  }

  @Test func anUpdateComesBeforeMaintenanceAndMaintenanceBeforeANotice() {
    let all = Self.status(maintenance: true, minVersion: "9", notice: Self.slow)
    #expect(Self.receive(all).0.screen == .updateRequired)
    let down = Self.status(maintenance: true, notice: Self.slow)
    #expect(Self.receive(down).0.screen == .maintenance(down.maintenance))
  }

  @Test func theNoticeShowsWhenNothingElseDoes() {
    #expect(Self.receive(Self.status(notice: Self.slow)).0.screen == .normal(notice: Self.slow))
  }

  @Test func aDismissedNoticeStaysDismissed() {
    let (shown, _) = Self.receive(Self.status(notice: Self.slow))
    let (dismissed, outputs) = ServiceStatusMachine.transition(shown, .noticeDismissed)
    #expect(dismissed.screen == .normal(notice: nil))
    #expect(outputs == [.rememberDismissed(Self.slow)])
    let (again, _) = Self.receive(Self.status(notice: Self.slow), in: dismissed)
    #expect(again.screen == .normal(notice: nil))
  }

  @Test func aNoticeWithNewWordsOrANewKeyShowsAgain() {
    let (shown, _) = Self.receive(Self.status(notice: Self.slow))
    let (dismissed, _) = ServiceStatusMachine.transition(shown, .noticeDismissed)
    let reworded = StatusMessage(key: Self.slow.key, text: "Notes are slow tonight.")
    #expect(
      Self.receive(Self.status(notice: reworded), in: dismissed).0.screen
        == .normal(notice: reworded))
    let rekeyed = StatusMessage(key: "notice.other", text: Self.slow.text)
    #expect(
      Self.receive(Self.status(notice: rekeyed), in: dismissed).0.screen
        == .normal(notice: rekeyed))
  }

  @Test func dismissingWithNoNoticeOnScreenDoesNothing() {
    let (down, _) = Self.receive(Self.status(maintenance: true, notice: Self.slow))
    let (next, outputs) = ServiceStatusMachine.transition(down, .noticeDismissed)
    #expect(next == down)
    #expect(outputs.isEmpty)
  }

  @Test func theEndOfMaintenanceIsAnnouncedOnce() {
    let (down, _) = Self.receive(Self.status(maintenance: true))
    let (up, outputs) = Self.receive(Self.status(), in: down)
    #expect(outputs == [.maintenanceEnded])
    #expect(up.screen == .normal(notice: nil))
    #expect(Self.receive(Self.status(), in: up).1.isEmpty)
  }

  @Test func maintenanceHeardTwiceIsNotAnEnd() {
    let (down, _) = Self.receive(Self.status(maintenance: true))
    #expect(Self.receive(Self.status(maintenance: true), in: down).1.isEmpty)
  }

  @Test func theLatestAnswerWinsWhicheverSourceItCameFrom() {
    let (down, _) = Self.receive(Self.status(maintenance: true))
    let (up, _) = Self.receive(.normal, in: down)
    let (downAgain, _) = Self.receive(Self.status(maintenance: true), in: up)
    #expect(downAgain.screen == .maintenance(Self.status(maintenance: true).maintenance))
  }
}
