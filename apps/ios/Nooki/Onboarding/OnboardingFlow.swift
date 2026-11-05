import Foundation
import Observation
import Transport
import Wire

/// The first launch: a welcome over the room, the server's questions, the cat's coat and name, an invite for the partner,
/// then home. Every step can be skipped. Answers are queued in a file and sent when the server can be reached
/// (`AnswerQueue`); the questions come from the server, or from the copy in the app when it can't be reached.
@MainActor
@Observable
final class OnboardingFlow {
    enum Page: Hashable {
        case welcome
        case question(OnboardingStep)
        case catCoat
        case catName
        case invite
    }

    static let doneKey = "onboardingDone"
    static let catCoatStep: OnboardingStepId = "cat_coat"
    static let catNameStep: OnboardingStepId = "cat_name"
    static let inviteStep: OnboardingStepId = "invite_partner"
    static let inviteSent: OnboardingOptionId = "sent"

    private(set) var catalogue: OnboardingResponse
    private(set) var index = 0
    private(set) var isFinished: Bool

    /// The options picked on each choice step, the value on each range step and the text on each text step.
    var picks: [OnboardingStepId: [OnboardingOptionId]] = [:]
    var values: [OnboardingStepId: Int] = [:]
    var texts: [OnboardingStepId: String] = [:]
    var catName = ""
    var coat: CatCoat
    /// The coat the room's cat wears; it changes once the picked coat is confirmed.
    private(set) var wornCoat: CatCoat
    /// The share sheet with the invite was opened.
    var invited = false

    @ObservationIgnored private let client: OnboardingClient
    @ObservationIgnored private let report: @Sendable ([ClientEvent]) async throws(TransportError) -> Void
    @ObservationIgnored private let queue: AnswerQueue
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let catNames: UserDefaults
    @ObservationIgnored private let canInvite: Bool
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let coatChanged: () -> Void
    @ObservationIgnored private var events: [ClientEvent] = []
    @ObservationIgnored private var viewed: Set<OnboardingStepId> = []
    @ObservationIgnored private var sending = false

    init(
        client: OnboardingClient,
        report: @escaping @Sendable ([ClientEvent]) async throws(TransportError) -> Void,
        queue: AnswerQueue,
        defaults: UserDefaults = .standard,
        catNames: UserDefaults = CatProfile.store,
        canInvite: Bool,
        bundled: OnboardingResponse = BundledOnboarding.load(),
        now: @escaping () -> Date = Date.init,
        coatChanged: @escaping () -> Void = {}
    ) {
        self.coatChanged = coatChanged
        coat = CatCoat.current(in: defaults)
        wornCoat = CatCoat.current(in: defaults)
        self.client = client
        self.report = report
        self.queue = queue
        self.defaults = defaults
        self.catNames = catNames
        self.canInvite = canInvite
        self.now = now
        catalogue = bundled
        isFinished = defaults.bool(forKey: Self.doneKey)
        #if DEBUG
        // For screenshots: `-onboardingPage 3` opens that page (the welcome is 0).
        index = max(defaults.integer(forKey: "onboardingPage"), 0)
        #endif
    }

    var pages: [Page] {
        [.welcome] + catalogue.steps.map(Page.question) + [.catCoat, .catName] + (canInvite ? [.invite] : [])
    }

    var page: Page { pages[min(index, pages.count - 1)] }

    /// How far along the steps after the welcome, from 0 to 1.
    var progress: Double { Double(index) / Double(max(pages.count - 1, 1)) }

    /// The server's questions replace the bundled ones until the first question is shown; after that the person
    /// keeps the set they started with. Also sends whatever is still queued from an earlier launch.
    func load() async {
        await send()
        guard let response = try? await client.fetch(), index == 0 else { return }
        catalogue = response
    }

    // MARK: Answering

    func toggle(_ option: OnboardingOption, in step: OnboardingStep) {
        switch step {
        case .single(let choice):
            picks[choice.id] = [option.id]
        case .multi(let choice):
            var picked = picks[choice.id] ?? []
            if picked.contains(option.id) {
                picked.removeAll { $0 == option.id }
            } else if option.exclusive == true {
                picked = [option.id]
            } else {
                let exclusive = Set(choice.options.filter { $0.exclusive == true }.map(\.id))
                picked.removeAll { exclusive.contains($0) }
                picked.append(option.id)
            }
            picks[choice.id] = picked
        case .range, .text:
            break
        }
    }

    /// The range's starting value: the middle, on a step.
    static func initialValue(_ range: OnboardingRangeStep) -> Int {
        let middle = (range.min + range.max) / 2
        return range.min + (middle - range.min) / range.step * range.step
    }

    /// The answer the Continue button would send, or nil while there is nothing to send.
    var answer: OnboardingAnswer? {
        switch page {
        case .welcome, .invite:
            return nil
        case .catCoat:
            return .single(option: OnboardingOptionId(coat.rawValue))
        case .question(let step):
            return Self.answer(to: step, picks: picks[step.id] ?? [], value: values[step.id], text: texts[step.id])
        case .catName:
            let name = catName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : .text(String(name.prefix(CatProfile.nameLimit)))
        }
    }

    static func answer(
        to step: OnboardingStep, picks: [OnboardingOptionId], value: Int?, text: String?
    ) -> OnboardingAnswer? {
        switch step {
        case .single: picks.first.map { .single(option: $0) }
        case .multi: picks.isEmpty ? nil : .multi(options: picks)
        case .range(let range): .range(value: value ?? initialValue(range))
        case .text(let field):
            (text?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
                $0.isEmpty ? nil : .text(String($0.prefix(field.maxLength)))
            }
        }
    }

    var stepId: OnboardingStepId? {
        switch page {
        case .welcome: nil
        case .question(let step): step.id
        case .catCoat: Self.catCoatStep
        case .catName: Self.catNameStep
        case .invite: Self.inviteStep
        }
    }

    var canSkip: Bool {
        switch page {
        case .welcome: false
        case .question(let step):
            switch step {
            case .single(let s), .multi(let s): s.skippable
            case .range(let s): s.skippable
            case .text(let s): s.skippable
            }
        case .catCoat, .catName, .invite: true
        }
    }

    // MARK: Moving

    func start() { advance() }

    func continueTapped() {
        switch page {
        case .welcome:
            advance()
        case .invite:
            record(invited ? .single(option: Self.inviteSent) : .skipped)
            advance()
        case .catCoat:
            wear(coat)
            record(answer ?? .skipped)
            advance()
        case .catName:
            let answer = answer
            if case .text(let name) = answer {
                catNames.set(name, forKey: CatProfile.nameKey)
            } else {
                catNames.removeObject(forKey: CatProfile.nameKey)
            }
            record(answer ?? .skipped)
            advance()
        case .question:
            guard let answer else { return }
            record(answer)
            advance()
        }
    }

    func skip() {
        guard canSkip else { return }
        if page == .catName { catNames.removeObject(forKey: CatProfile.nameKey) }
        if page == .catCoat {
            coat = .grey
            wear(.grey)
        }
        record(.skipped)
        advance()
    }

    func back() {
        guard index > 0 else { return }
        index -= 1
    }

    /// Counts the step as seen, once per launch.
    func appeared() {
        guard let stepId, viewed.insert(stepId).inserted else { return }
        events.append(ClientEvent(.onboardingStepViewed, detail: stepId.rawValue))
        Task { await send() }
    }

    private func wear(_ coat: CatCoat) {
        defaults.set(coat.rawValue, forKey: CatCoat.key)
        guard coat != wornCoat else { return }
        coatChanged()
        wornCoat = coat
    }

    private func advance() {
        if index + 1 < pages.count {
            index += 1
        } else {
            defaults.set(true, forKey: Self.doneKey)
            isFinished = true
        }
    }

    private func record(_ answer: OnboardingAnswer) {
        guard let stepId else { return }
        let answeredAt = Int((now().timeIntervalSince1970 * 1000).rounded())
        queue.add(SaveOnboardingAnswerRequest(
            version: catalogue.version, stepId: stepId, answer: answer, answeredAt: answeredAt))
        events.append(ClientEvent(answer == .skipped ? .onboardingStepSkipped : .onboardingStepAnswered,
                                  detail: stepId.rawValue))
        Task { await send() }
    }

    /// Sends the queued answers, then the events, until both are empty or the server can't be reached. Events
    /// that could not be sent wait for the next call; the server refusing them as malformed drops them, since no
    /// retry would change that.
    private func send() async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        while await queue.flush(with: client) {
            let batch = Array(events.prefix(ReportEventsRequest.maxEvents))
            guard !batch.isEmpty else {
                if queue.pending.isEmpty { return }
                continue
            }
            do {
                try await report(batch)
            } catch {
                guard error == .api(.invalidRequest) else { return }
            }
            events.removeFirst(min(batch.count, events.count))
        }
    }
}
