#if DEBUG || LABS_YES
import DecorInterface
import Design
import FeatureRaid
import RaidInterface
import SwiftUI

/// Night raid, the prototype: two people and one phone. The keeper hides the jar and sets defences on the pair's own
/// room, the runner steers the cat at it for 45 seconds, both watch the run again, and they swap.
struct RaidScreen: View {
    let cat: String

    @State private var store: RaidStore
    @State private var finger: RaidPoint?
    @State private var jump = false
    @State private var sniff = false

    init(layout: DecorLayout, cat: String) {
        self.cat = cat
        _store = State(initialValue: .raid(board: RaidBoard(layout: layout)))
    }

    private var isRunning: Bool { if case .running = store.state { true } else { false } }
    private var isReplaying: Bool { if case .replaying = store.state { true } else { false } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            switch store.state {
            case .setting(let draft): keeper(draft)
            case .handover: handover
            case .running(let session): runner(session.run)
            case .finished(let finished): after(finished)
            case .replaying(let replay): watching(replay)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .bottomActions(primary: { primary }, secondary: { secondary })
        .background(Ink.screen.ignoresSafeArea())
        .navigationTitle("Night raid")
        .interactiveDismissDisabled()
        .task(id: isRunning) {
            guard isRunning else { return }
            await ticking {
                store.send(.tick(RaidInput(steer: finger, jump: jump, sniff: sniff)))
                jump = false
                sniff = false
            }
        }
        .task(id: isReplaying) {
            guard isReplaying else { return }
            await ticking { store.send(.replayTick) }
        }
    }

    /// Calls `step` at the simulation's rate until the task is cancelled.
    private func ticking(_ step: () -> Void) async {
        let clock = ContinuousClock()
        var next = clock.now
        while !Task.isCancelled {
            step()
            next += .seconds(1) / RaidRules.tickRate
            try? await clock.sleep(until: next)
        }
    }

    // MARK: Keeper

    private func keeper(_ draft: RaidMachine.Draft) -> some View {
        Group {
            Text(draft.round.isMultiple(of: 2) ? "Keeper, your turn" : "Swap: the runner is the keeper now")
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
            Text("Put the treat jar down, then up to three defences. Keep the screen to yourself.")
                .font(.ourioCallout)
                .foregroundStyle(Ink.textSecondary)
            RaidBoardCanvas(board: draft.board, jar: draft.jar,
                            marks: draft.defences.map { .init(defence: $0, place: $0.at) },
                            pending: pending(draft.tool)) { point in
                if let point { finger = point } else if let place = finger {
                    finger = nil
                    store.send(.tapped(place))
                }
            }
            .accessibilityIdentifier("raidBoard")
            FlowRow {
                tool("Jar", "takeoutbag.and.cup.and.straw.fill", .jar, draft)
                tool("Vacuum", "circle.circle.fill", .vacuum, draft)
                tool("Box", "shippingbox.fill", .box, draft)
                tool("Cucumber", "leaf.fill", .cucumber, draft)
                tool("Squeaky board", "speaker.wave.2.fill", .squeakyBoard, draft)
            }
            Text(hint(draft))
                .font(.ourioCaption)
                .foregroundStyle(draft.problem == nil ? Ink.textSecondary : Ink.destructive)
        }
    }

    private func pending(_ tool: RaidMachine.Tool) -> RaidPoint? {
        if case .vacuumEnd(let from) = tool { from } else { nil }
    }

    private func tool(_ title: String, _ symbol: String, _ tool: RaidMachine.Tool, _ draft: RaidMachine.Draft)
        -> some View
    {
        let selected = draft.tool == tool || (tool == .vacuum && pending(draft.tool) != nil)
        return FilterChip(title, symbol: symbol, isSelected: selected) { store.send(.chose(tool)) }
    }

    private func hint(_ draft: RaidMachine.Draft) -> String {
        switch draft.problem {
        case .jarTooNearStart: return "The jar is too near where \(cat) starts (the small dot)."
        case .defenceNearStart: return "A defence is too near where \(cat) starts."
        case .defenceOnFurniture: return "A defence has to stand on the floor."
        case .tooManyDefences: return "Three defences at most."
        case nil: break
        }
        switch draft.tool {
        case .jar: return "Tap the floor or a piece of furniture for the jar."
        case .vacuum: return "Tap where the vacuum starts. Touching it, \(cat) rides it away."
        case .vacuumEnd: return "Now tap where it turns round."
        case .box: return "Tap for the box. Walking past it slowly, \(cat) ends up in it for four seconds."
        case .cucumber: return "Tap for the cucumber. Hidden: \(cat) leaps back from it, once."
        case .squeakyBoard: return "Tap for the squeaky board. Hidden: run over it and the lamp comes on."
        }
    }

    // MARK: Runner

    private var handover: some View {
        Group {
            Text("Pass the phone")
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
            Text("Runner: you are \(cat), and you have 45 seconds to reach the jar and stand by it for a moment.")
                .font(.ourioBody)
                .foregroundStyle(Ink.text)
            Text("Drag on the floor and \(cat) runs to your finger. Keep the finger close to creep. Jump hops onto "
                + "furniture, and over what is on the floor. Sniff shows what is hidden nearby, three times. If the "
                + "lamp comes on, lift your finger and freeze.")
                .font(.ourioCallout)
                .foregroundStyle(Ink.textSecondary)
        }
    }

    private func runner(_ run: RaidRun) -> some View {
        Group {
            HStack(spacing: Space.m) {
                Text(run.lampIsOn ? "Freeze!" : "\(Int(run.secondsLeft.rounded(.up))) s")
                    .font(.ourioValueDigits)
                    .foregroundStyle(run.lampIsOn ? Ink.destructive : Ink.text)
                    .accessibilityIdentifier("raidClock")
                ProgressBar(value: run.secondsLeft, total: Double(RaidRules.seconds))
            }
            board(run, showAll: false) { finger = $0 }
                .haptic(.rejected, trigger: Feel(run).trouble)
                .haptic(.tap, trigger: Feel(run).found)
            HStack(spacing: Space.m) {
                PillButton("Jump", symbol: "arrow.up.forward", fullWidth: true) { jump = true }
                    .accessibilityIdentifier("raidJump")
                PillButton("Sniff \(run.sniffsLeft)", symbol: "nose.fill", fullWidth: true) { sniff = true }
                    .disabled(run.sniffsLeft == 0)
                    .accessibilityIdentifier("raidSniff")
            }
        }
    }

    private func board(_ run: RaidRun, showAll: Bool, touch: @escaping (RaidPoint?) -> Void) -> some View {
        let marks = run.level.defences
            .filter { showAll || run.shows($0) }
            .map { RaidBoardCanvas.Mark(defence: $0, place: run.vacuumPlace($0)) }
        return RaidBoardCanvas(board: run.board, jar: run.level.jar, marks: marks, cat: mark(run),
                               lampOn: run.lampIsOn,
                               pawing: Double(run.pawing) / Double(RaidRules.pawTicks), touch: touch)
    }

    private func mark(_ run: RaidRun) -> RaidBoardCanvas.Cat {
        var lift = run.on == nil ? 0.0 : 0.5
        var inBox = false
        switch run.mode {
        case .jumping, .startled: lift = 1
        case .carried: lift = 0.8
        case .inBox: inBox = true
        case .free, .riding: break
        }
        return RaidBoardCanvas.Cat(at: run.cat, heading: run.heading, lift: lift, inBox: inBox)
    }

    // MARK: After

    private func after(_ finished: RaidMachine.Finished) -> some View {
        Group {
            Text(verdict(finished.outcome))
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
                .accessibilityIdentifier("raidVerdict")
            board(finished.run, showAll: true) { _ in }
            Text("Everything the keeper set is shown now.")
                .font(.ourioCaption)
                .foregroundStyle(Ink.textSecondary)
        }
    }

    private func verdict(_ outcome: RaidOutcome) -> String {
        switch outcome {
        case .got(let seconds):
            "\(cat) got the jar in \(seconds.formatted(.number.precision(.fractionLength(1)))) s."
        case .kept(let closest):
            "The keeper kept it. \(cat) came within \(Int((closest * 100).rounded())) cm."
        }
    }

    private func watching(_ replay: RaidMachine.Replay) -> some View {
        Group {
            HStack(spacing: Space.m) {
                Text("Replay")
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.text)
                ProgressBar(value: Double(replay.index), total: Double(max(1, replay.finished.inputs.count)))
            }
            board(replay.run, showAll: true) { _ in }
        }
    }

    // MARK: Actions

    @ViewBuilder private var primary: some View {
        switch store.state {
        case .setting(let draft):
            PrimaryButton("Hand the phone over", symbol: "arrow.left.arrow.right") { store.send(.handedOver) }
                .disabled(!draft.canHandOver)
                .accessibilityIdentifier("raidHandOver")
        case .handover:
            PrimaryButton("Start the run", symbol: "play.fill") { store.send(.started) }
                .accessibilityIdentifier("raidStart")
        case .running:
            EmptyView()
        case .finished:
            PrimaryButton("Watch it again", symbol: "play.rectangle.fill") { store.send(.watch) }
                .accessibilityIdentifier("raidWatch")
        case .replaying:
            PrimaryButton("Swap and play again", symbol: "arrow.triangle.2.circlepath") { store.send(.again) }
        }
    }

    @ViewBuilder private var secondary: some View {
        switch store.state {
        case .setting(let draft):
            if let last = draft.defences.last {
                SecondaryButton("Take the last one back", symbol: "arrow.uturn.backward") {
                    store.send(.removed(last.id))
                }
            }
        case .finished:
            SecondaryButton("Swap and play again", symbol: "arrow.triangle.2.circlepath") { store.send(.again) }
                .accessibilityIdentifier("raidAgain")
        case .replaying:
            SecondaryButton("Skip", symbol: "forward.end.fill") { store.send(.replayEnded) }
        case .handover, .running:
            EmptyView()
        }
    }
}

/// What in a run is worth a haptic, as values that change when it happens.
private struct Feel {
    /// Sprung traps: a fright, the box, a ride, being carried.
    let trouble: Int
    /// Hidden things found and sniffs used.
    let found: Int

    init(_ run: RaidRun) {
        switch run.mode {
        case .free, .jumping: trouble = 0
        case .startled: trouble = 1
        case .inBox: trouble = 2
        case .riding: trouble = 3
        case .carried: trouble = 4
        }
        found = run.revealed.count + RaidRules.sniffs - run.sniffsLeft
    }
}
#endif
