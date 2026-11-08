import FeaturePairing
import Foundation
import Synchronization
import Testing
import Transport
import Wire
@testable import Billet

/// What the fake server was sent.
private final class Sent: Sendable {
    let answers = Mutex<[SaveOnboardingAnswerRequest]>([])
    let events = Mutex<[ClientEvent]>([])
    /// The error each save fails with, if any.
    let failure = Mutex<TransportError?>(nil)
}

private func text(_ en: String) -> LocalizedText { LocalizedText(en: en, ru: en) }

private let goals = OnboardingStep.multi(OnboardingChoiceStep(
    id: "goals", title: text("Goals"),
    options: [
        OnboardingOption(id: "closer", label: text("Closer")),
        OnboardingOption(id: "fun", label: text("Fun")),
        OnboardingOption(id: "exploring", label: text("Just exploring"), exclusive: true),
        OnboardingOption(id: "widgets", label: text("Widgets")),
    ]))
private let age = OnboardingStep.single(OnboardingChoiceStep(
    id: "age", title: text("Age"),
    options: [
        OnboardingOption(id: "age-under-13", label: text("Under 13")), OnboardingOption(id: "a", label: text("A")),
        OnboardingOption(id: "b", label: text("B")),
    ]))
private let catalogue = OnboardingResponse(version: "v1", steps: [age, goals])

@MainActor
private func makeFlow(
    sent: Sent = Sent(), server: OnboardingResponse? = nil, canInvite: Bool = true, hasServer: Bool = false,
    asksTogetherSince: Bool = false, togetherSinceChosen: @escaping (Date) -> Void = { _ in },
    defaults reused: UserDefaults? = nil
) -> (OnboardingFlow, UserDefaults, URL) {
    let suite = "onboarding-\(UUID().uuidString)"
    let defaults = reused ?? UserDefaults(suiteName: suite)!
    let file = URL.temporaryDirectory.appending(path: "\(suite)/answers.json")
    let client = OnboardingClient(
        fetch: { () async throws(TransportError) in
            guard let server else { throw .network("offline") }
            return server
        },
        save: { [sent] (request) async throws(TransportError) in
            if let failure = sent.failure.withLock({ $0 }) { throw failure }
            sent.answers.withLock { $0.append(request) }
        })
    let flow = OnboardingFlow(
        client: client,
        report: { [sent] (events) async throws(TransportError) in sent.events.withLock { $0.append(contentsOf: events) } },
        queue: AnswerQueue(file: file), defaults: defaults, catNames: defaults, canInvite: canInvite,
        hasServer: hasServer, asksTogetherSince: asksTogetherSince, togetherSinceChosen: togetherSinceChosen,
        bundled: catalogue,
        now: { Date(timeIntervalSince1970: 1_000) })
    return (flow, defaults, file)
}

/// Lets the flow's background sends run until `done`, or gives up after a while.
@MainActor
private func settle(_ done: () -> Bool) async {
    for _ in 0..<200 where !done() { await Task.yield() }
}

@MainActor
struct OnboardingFlowTests {
    @Test func walksWelcomeQuestionsNameAndInvite() {
        let (flow, _, _) = makeFlow()
        #expect(flow.pages == [.welcome, .question(age), .question(goals), .catCoat, .catName, .invite])
        #expect(makeFlow(canInvite: false).0.pages.last == .catName)
    }

    @Test func everyStepCanBeSkippedAndTheLastOneFinishes() async {
        let sent = Sent()
        let (flow, defaults, _) = makeFlow(sent: sent)
        flow.start()
        for _ in 0..<4 { flow.skip() }
        #expect(!flow.canSkip)
        flow.continueTapped()
        #expect(flow.isFinished)
        #expect(defaults.bool(forKey: OnboardingFlow.doneKey))
        await settle { sent.answers.withLock { $0.count } == 5 }
        let answers = sent.answers.withLock { $0 }
        #expect(answers.map(\.stepId) == ["age", "goals", "cat_coat", "cat_name", "invite_partner"])
        #expect(answers.allSatisfy { $0.answer == .skipped && $0.answeredAt == 1_000_000 && $0.version == "v1" })
        #expect(sent.events.withLock { $0 }.contains(ClientEvent(.onboardingStepSkipped, detail: "goals")))
    }

    @Test func leavingTheWelcomeEitherWayAcceptsTheTerms() {
        let (flow, defaults, _) = makeFlow()
        flow.start()
        #expect(flow.page == .welcome)
        #expect(!flow.termsAccepted)
        flow.continueTapped()
        #expect(flow.termsAccepted)

        let (joiner, joinerDefaults, _) = makeFlow()
        joiner.start()
        joiner.join()
        #expect(joiner.termsAccepted)
        #expect(joinerDefaults.object(forKey: OnboardingFlow.termsAcceptedKey) is Date)
        #expect(defaults.object(forKey: OnboardingFlow.termsAcceptedKey) is Date)
    }

    @Test func continueNeedsAnAnswer() {
        let (flow, _, _) = makeFlow()
        flow.start()
        flow.continueTapped()
        #expect(flow.page == .question(age))
        flow.toggle(OnboardingOption(id: "b", label: text("B")), in: age)
        #expect(flow.answer == .single(option: "b"))
        flow.continueTapped()
        #expect(flow.page == .question(goals))
    }

    @Test func anExclusiveOptionClearsTheOthers() {
        let (flow, _, _) = makeFlow()
        guard case .multi(let choice) = goals else { return }
        flow.toggle(choice.options[0], in: goals)
        flow.toggle(choice.options[1], in: goals)
        #expect(flow.picks["goals"] == ["closer", "fun"])
        flow.toggle(choice.options[2], in: goals)
        #expect(flow.picks["goals"] == ["exploring"])
        flow.toggle(choice.options[0], in: goals)
        #expect(flow.picks["goals"] == ["closer"])
    }

    @Test func theNamedCatKeepsItsNameAndASkippedOneStaysMochi() {
        let (flow, defaults, _) = makeFlow()
        flow.start()
        flow.skip()
        flow.skip()
        flow.skip()
        flow.catName = "  Tofu "
        flow.continueTapped()
        #expect(CatProfile.name(in: defaults) == "Tofu")
        flow.back()
        flow.skip()
        #expect(CatProfile.name(in: defaults) == "Mochi")
    }

    @Test func theServerQuestionsReplaceTheBundledOnesOnlyBeforeTheFirstQuestion() async {
        let server = OnboardingResponse(version: "v2", steps: [goals])
        let (fresh, _, _) = makeFlow(server: server)
        await fresh.load()
        #expect(fresh.catalogue == server)

        let (started, _, _) = makeFlow(server: server)
        started.start()
        await started.load()
        #expect(started.catalogue == catalogue)
    }

    @Test func aPickedCoatIsWornAndSentAndASkippedOneIsGrey() async {
        let sent = Sent()
        let (flow, defaults, _) = makeFlow(sent: sent)
        var changes = 0
        let coated = OnboardingFlow(
            client: .offline, report: { (_) async throws(TransportError) in }, queue: AnswerQueue(
                file: URL.temporaryDirectory.appending(path: "coat-\(UUID().uuidString)/a.json")),
            defaults: defaults, catNames: defaults, canInvite: false,
            bundled: OnboardingResponse(version: "v1", steps: []),
            coatChanged: { changes += 1 })
        coated.start()
        #expect(coated.page == .catCoat)
        coated.coat = .ginger
        coated.continueTapped()
        #expect(CatCoat.current(in: defaults) == .ginger)
        #expect(coated.wornCoat == .ginger)
        #expect(changes == 1)
        coated.back()
        coated.skip()
        #expect(CatCoat.current(in: defaults) == .grey)
        #expect(changes == 2)

        flow.start()
        flow.skip()
        flow.skip()
        flow.coat = .cream
        flow.continueTapped()
        await settle { sent.answers.withLock { $0.count } == 3 }
        #expect(sent.answers.withLock { $0.last?.answer } == .single(option: "cream"))
    }

    @Test func whoeverWasInvitedEntersTheCodeAndLeavesTheInvite() {
        let (flow, _, _) = makeFlow(hasServer: true, asksTogetherSince: true)
        #expect(flow.pages == [
            .welcome, .question(age), .question(goals), .togetherSince, .catCoat, .catName, .invite, .notifications,
        ])
        flow.join(code: "K7QM4R2XHP")
        #expect(flow.page == .join)
        #expect(flow.joinCode == "K7QM4R2XHP")
        #expect(flow.pages == [
            .welcome, .join, .question(age), .question(goals), .togetherSince, .catCoat, .catName, .notifications,
        ])
        flow.partnerJoined()
        #expect(flow.page == .question(age))
        flow.back()
        flow.back()
        #expect(flow.page == .welcome)
        #expect(flow.pages.contains(.invite))
    }

    @Test func underThirteenStopsAndSendsNoAge() async {
        let sent = Sent()
        let (flow, defaults, _) = makeFlow(sent: sent)
        flow.start()
        guard case .single(let choice) = age else { return }
        flow.toggle(choice.options[0], in: age)
        flow.continueTapped()
        #expect(flow.page == .stopped)
        #expect(defaults.bool(forKey: OnboardingFlow.stoppedKey))
        await settle { sent.events.withLock { $0 }.contains(ClientEvent(.ageGateStopped)) }
        #expect(sent.events.withLock { $0 }.contains(ClientEvent(.ageGateStopped)))
        #expect(sent.answers.withLock { $0 }.isEmpty)
        #expect(makeFlow(defaults: defaults).0.page == .stopped)
    }

    @Test func theWidgetHowToFollowsTheGoals() {
        let (flow, _, _) = makeFlow()
        #expect(!flow.pages.contains(.widget))
        guard case .multi(let choice) = goals else { return }
        flow.toggle(choice.options[3], in: goals)
        #expect(flow.pages.last == .widget)
    }

    @Test func theDayTheStoryStartedStaysOnThePhone() async {
        let sent = Sent()
        var chosen: Date?
        let (flow, _, _) = makeFlow(sent: sent, asksTogetherSince: true, togetherSinceChosen: { chosen = $0 })
        flow.start()
        flow.skip()
        flow.skip()
        #expect(flow.page == .togetherSince)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        flow.togetherSince = day
        flow.continueTapped()
        #expect(chosen == day)
        #expect(flow.page == .catCoat)
        await settle { sent.answers.withLock { $0.count } == 2 }
        #expect(sent.answers.withLock { $0 }.map(\.stepId) == ["age", "goals"])
    }

    @Test func aClosedAppOpensOnThePageItWasOnWithItsQuestionsAndPicks() async {
        let server = OnboardingResponse(version: "v2", steps: [goals, age])
        let (flow, defaults, _) = makeFlow(server: server)
        await flow.load()
        flow.start()
        guard case .multi(let choice) = goals else { return }
        flow.toggle(choice.options[3], in: goals)
        flow.continueTapped()
        let relaunched = makeFlow(defaults: defaults).0
        #expect(relaunched.catalogue == server)
        #expect(relaunched.page == .question(age))
        #expect(relaunched.pages.last == .widget)
    }

    @Test func aRangeStartsInTheMiddleOnAStep() {
        let range = OnboardingRangeStep(id: "r", title: text("R"), min: 0, max: 10, step: 3)
        #expect(OnboardingFlow.initialValue(range) == 3)
        #expect(OnboardingFlow.answer(to: .range(range), picks: [], value: nil, text: nil) == .range(value: 3))
    }
}

@MainActor
struct AnswerQueueTests {
    private func request(_ step: OnboardingStepId, _ answer: OnboardingAnswer = .skipped) -> SaveOnboardingAnswerRequest {
        SaveOnboardingAnswerRequest(version: "v1", stepId: step, answer: answer, answeredAt: 1)
    }

    private func client(_ sent: Sent) -> OnboardingClient {
        OnboardingClient(
            fetch: { () async throws(TransportError) in throw .network("offline") },
            save: { [sent] (request) async throws(TransportError) in
                if let failure = sent.failure.withLock({ $0 }) { throw failure }
                sent.answers.withLock { $0.append(request) }
            })
    }

    @Test func anOfflineAnswerWaitsAcrossLaunches() async {
        let file = URL.temporaryDirectory.appending(path: "queue-\(UUID().uuidString)/answers.json")
        let sent = Sent()
        sent.failure.withLock { $0 = .network("offline") }
        let queue = AnswerQueue(file: file)
        queue.add(request("age"))
        #expect(await queue.flush(with: client(sent)) == false)

        sent.failure.withLock { $0 = nil }
        let relaunched = AnswerQueue(file: file)
        #expect(relaunched.pending.map(\.stepId) == ["age"])
        #expect(await relaunched.flush(with: client(sent)))
        #expect(relaunched.pending.isEmpty)
        #expect(AnswerQueue(file: file).pending.isEmpty)
    }

    @Test func anAnswerTheServerRefusesIsDropped() async {
        let sent = Sent()
        sent.failure.withLock { $0 = .api(.invalidRequest) }
        let queue = AnswerQueue(file: URL.temporaryDirectory.appending(path: "queue-\(UUID().uuidString)/a.json"))
        queue.add(request("gone"))
        #expect(await queue.flush(with: client(sent)))
        #expect(queue.pending.isEmpty)
    }

    @Test func onlyTheLatestAnswerToAStepWaits() {
        let queue = AnswerQueue(file: URL.temporaryDirectory.appending(path: "queue-\(UUID().uuidString)/a.json"))
        queue.add(request("age"))
        queue.add(request("age", .single(option: "b")))
        #expect(queue.pending == [request("age", .single(option: "b"))])
    }

    @Test func theBundledQuestionsDecode() {
        let bundled = BundledOnboarding.load(from: .main)
        #expect(bundled.steps.count >= 1)
    }

    // MARK: Pairing errors, invite input, welcome script

    @Test func aWrongCodeIsNeverShownOnTheInviteStep() {
        let wrong = PairingMachine.State.choosing(failure: .invalidCode, request: 3)
        #expect(OnboardingView.failure(in: wrong, on: .join) == .invalidCode)
        #expect(OnboardingView.failure(in: wrong, on: .invite) == nil)
        #expect(OnboardingView.failure(in: wrong, on: .welcome) == nil)
        let down = PairingMachine.State.choosing(failure: .unavailable, request: 1)
        #expect(OnboardingView.failure(in: down, on: .invite) == .unavailable)
        #expect(OnboardingView.failure(in: .waiting(code: "A", expiresAt: 1, request: 1), on: .join) == nil)
    }

    @Test func cancellingClearsTheFailure() {
        let wrong = PairingMachine.State.choosing(failure: .invalidCode, request: 3)
        let (next, outputs) = PairingMachine.transition(wrong, .cancelled)
        #expect(next == .choosing(failure: nil, request: 3))
        #expect(outputs.isEmpty)
    }

    @Test func theInviteStepHasNoSkipSinceLaterIsItsOwnButton() {
        let (flow, _, _) = makeFlow()
        flow.start()
        for _ in 0..<4 { flow.skip() }
        #expect(flow.page == .invite)
        #expect(!flow.canSkip)
    }

    @Test func anInviteIsRecognisedInEveryShapeItComes() {
        #expect(InviteInput.code(in: "K7QM4R2XHP") == "K7QM4R2XHP")
        #expect(InviteInput.code(in: " k7qm 4r2x hp\n") == "K7QM4R2XHP")
        #expect(InviteInput.code(in: "https://api.example.com/i/K7QM4R2XHP") == "K7QM4R2XHP")
        #expect(InviteInput.code(in: "nooki://invite/K7QM4R2XHP") == "K7QM4R2XHP")
        #expect(InviteInput.code(in: "hello there, see you at 7") == nil)
        #expect(InviteInput.code(in: "K7QM4R2X") == nil)
        #expect(InviteInput.code(in: "https://example.com/i/short") == nil)
        #expect(InviteInput.code(in: "abcd2345efghjklm npqrstuvwx") == "ABCD2345EFGHJKLMNPQRSTUVWX")
        #expect(OnboardingView.code(from: String(repeating: "A", count: 30)).count == InviteCode.reviewLength)
    }

    @Test func theWelcomeScriptIsDeterministicAndEndsSettled() {
        let script = WelcomeScript.standard
        for beat in script.cues.map(\.beat) {
            #expect(script.progress(beat, at: -1) == 0)
            #expect(script.progress(beat, at: script.duration) == 1)
            var last = 0.0
            for step in 0...40 {
                let now = script.progress(beat, at: script.duration * Double(step) / 40)
                #expect(now >= last)
                last = now
            }
        }
        #expect(script.progress(.title, at: 1.3) == script.progress(.title, at: 1.3))
        #expect(script.started(at: 0) == [.cat])
        #expect(script.started(at: script.duration).count == script.cues.count)
        #expect(script.duration < 3.5)
    }
}
