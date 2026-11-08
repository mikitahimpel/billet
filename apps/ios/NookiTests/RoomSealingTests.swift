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

    private func mount(_ shell: Shell, input: RoomInput, controller: RoomController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIHostingController(rootView: ShellView(shell: shell, input: input, controller: controller))
        window.makeKeyAndVisible()
        return window
    }

    /// A window left behind would keep evaluating its views while the next test counts.
    private func unmount(_ window: UIWindow) async throws {
        window.rootViewController = nil
        window.isHidden = true
        try await settle()
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(150)) }

    private let visible = RoomInput(scene: .home, coat: .grey, visibility: .visible)

    @Test func changesOutsideTheRoomDoNotReEvaluateIt() async throws {
        let controller = RoomController(usesStandIn: true)
        let shell = Shell()
        let window = mount(shell, input: visible, controller: controller)
        try await settle()
        // The first pass after mounting is SwiftUI's own: it has no earlier host to compare with yet.
        shell.coins = 1
        try await settle()
        controller.probe.reset()
        let shellBefore = shell.bodies

        for coins in 2...6 {
            shell.coins = coins
            try await settle()
        }

        #expect(shell.bodies > shellBefore, "the shell did re-evaluate for the coins")
        #expect(controller.probe.hostBodies == 0)
        #expect(controller.probe.stageBodies == 0)
        try await unmount(window)
    }

    @Test func theRoomsOwnTicksDoNotReachTheShell() async throws {
        let controller = RoomController(usesStandIn: true)
        let shell = Shell()
        let window = mount(shell, input: visible, controller: controller)
        try await settle()
        controller.probe.reset()
        let shellBefore = shell.bodies

        // A few seconds of ticks at 60 Hz that change nothing the shell reads.
        for _ in 0..<600 {
            controller.refreshStatus()
            await Task.yield()
        }
        try await settle()

        #expect(shell.bodies == shellBefore)
        #expect(controller.probe.hostBodies == 0)
        #expect(controller.status == CatStatus())
        try await unmount(window)
    }

    @Test func aGameChangesTheStageAndNothingOutside() async throws {
        let controller = RoomController(usesStandIn: true)
        let shell = Shell()
        let window = mount(shell, input: visible, controller: controller)
        try await settle()
        controller.probe.reset()
        let shellBefore = shell.bodies

        controller.play(.laser)
        try await settle()
        controller.endGame()
        try await settle()

        #expect(controller.probe.stageBodies >= 1)
        #expect(controller.game == nil)
        #expect(controller.probe.hostBodies == 0)
        #expect(shell.bodies == shellBefore)
        try await unmount(window)
    }

    @Test func aChangedInputReEvaluatesTheHost() async throws {
        let controller = RoomController(usesStandIn: true)
        let shell = Shell()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host = UIHostingController(rootView: ShellView(shell: shell, input: visible, controller: controller))
        window.rootViewController = host
        window.makeKeyAndVisible()
        try await settle()
        controller.probe.reset()

        host.rootView = ShellView(
            shell: shell, input: RoomInput(scene: .home, coat: .grey, visibility: .covered), controller: controller)
        try await settle()

        #expect(controller.probe.hostBodies == 1)
        try await unmount(window)
    }
}
