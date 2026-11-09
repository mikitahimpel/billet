import Observation
import RoomInterface
import SwiftUI
import Testing
import UIKit
@testable import Billet

/// The Room is sealed: what changes outside it doesn't re-evaluate it, and what changes inside it doesn't reach
/// the shell. The stand-in controller is the real host and stage without RealityKit, which CI's Macs can't draw.
@MainActor
@Suite(.serialized)
struct RoomSealingTests {
    @Observable
    final class Shell {
        var coins = 0
        @ObservationIgnored var bodies = 0
    }

    struct ShellView: View {
        let shell: Shell
        let input: RoomInput
        let controller: RoomController

        var body: some View {
            let _ = shell.bodies += 1
            VStack {
                Text("\(shell.coins) coins")
                RoomHost(input: input, controller: controller).equatable()
            }
        }
    }

    /// Mounts the shell and returns once shell changes stop reaching the host: early on, traits and the first frame
    /// give every view extra SwiftUI passes that end when the machine allows. Quiet means several applied changes in a
    /// row with no host pass; the probe is then reset, so a test counts only what it does.
    private func mount(
        _ shell: Shell, input: RoomInput, controller: RoomController
    ) async throws -> (UIWindow, UIHostingController<ShellView>) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host = UIHostingController(rootView: ShellView(shell: shell, input: input, controller: controller))
        window.rootViewController = host
        window.makeKeyAndVisible()
        try await wait("the first pass") { shell.bodies >= 1 && controller.probe.hostBodies >= 1 }
        var quiet = 0
        for _ in 0..<500 where quiet < 5 {
            controller.probe.reset()
            try await flush(shell)
            quiet = controller.probe.hostBodies == 0 ? quiet + 1 : 0
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(quiet >= 5, "changes to the shell still reach the host after mounting")
        controller.probe.reset()
        return (window, host)
    }

    /// Changes the shell and returns once it has re-evaluated: any update still pending runs by then too, in that
    /// pass or before it, so what a test then counts is final.
    private func flush(_ shell: Shell) async throws {
        let before = shell.bodies
        shell.coins += 1
        try await wait("the shell's pass") { shell.bodies > before }
    }

    /// Polls until `condition` holds; the limit only bounds a broken run, a passing one never waits for it.
    private func wait(_ what: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("timed out waiting for \(what)")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func unmount(_ window: UIWindow) {
        window.rootViewController = nil
        window.isHidden = true
    }

    private let visible = RoomInput(scene: .home, coat: .grey, visibility: .visible)

    @Test func changesOutsideTheRoomDoNotReEvaluateIt() async throws {
        let controller = RoomController(usesStandIn: true)
        let shell = Shell()
        let (window, _) = try await mount(shell, input: visible, controller: controller)
        let shellBefore = shell.bodies

        for _ in 2...6 { try await flush(shell) }

        #expect(shell.bodies > shellBefore, "the shell did re-evaluate for the coins")
        #expect(controller.probe.hostBodies == 0)
        #expect(controller.probe.stageBodies == 0)
        unmount(window)
    }

    @Test func theRoomsOwnTicksDoNotReachTheShell() async throws {
        let controller = RoomController(usesStandIn: true)
        let shell = Shell()
        let (window, _) = try await mount(shell, input: visible, controller: controller)
        let shellBefore = shell.bodies

        // A few seconds of ticks at 60 Hz that change nothing the shell reads.
        for _ in 0..<600 {
            controller.refreshStatus()
            await Task.yield()
        }
        try await flush(shell)

        #expect(shell.bodies == shellBefore + 1, "only the flush re-evaluated the shell")
        #expect(controller.probe.hostBodies == 0)
        #expect(controller.status == CatStatus())
        unmount(window)
    }

    @Test func aGameChangesTheStageAndNothingOutside() async throws {
        let controller = RoomController(usesStandIn: true)
        let shell = Shell()
        let (window, _) = try await mount(shell, input: visible, controller: controller)
        let shellBefore = shell.bodies

        controller.play(.laser)
        try await wait("the stage's pass for the game") { controller.probe.stageBodies >= 1 }
        let stageDuringGame = controller.probe.stageBodies
        controller.endGame()
        try await wait("the stage's pass for the game's end") { controller.probe.stageBodies > stageDuringGame }
        try await flush(shell)

        #expect(controller.game == nil)
        #expect(controller.probe.hostBodies == 0)
        #expect(shell.bodies == shellBefore + 1, "only the flush re-evaluated the shell")
        unmount(window)
    }

    @Test func aChangedInputReEvaluatesTheHost() async throws {
        let controller = RoomController(usesStandIn: true)
        let shell = Shell()
        let (window, host) = try await mount(shell, input: visible, controller: controller)

        host.rootView = ShellView(
            shell: shell, input: RoomInput(scene: .home, coat: .grey, visibility: .covered), controller: controller)
        try await wait("the host's pass for the new input") { controller.probe.hostBodies >= 1 }
        try await flush(shell)

        #expect(controller.probe.hostBodies == 1)
        unmount(window)
    }
}
