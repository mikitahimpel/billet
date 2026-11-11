import Foundation
import MomentsInterface
import Observation
import WidgetInterface
import WidgetUI
import ProfileInterface
import Transport
import UsInterface
import Wire

/// First launch: welcome (or the partner's code), the server's questions, the start date, the cat's coat and name,
/// an invite, notifications and the widget, then home. Every step but the code can be skipped; under 13 it stops.
/// Answers queue in a file until the server is reachable (`AnswerQueue`); questions fall back to the bundled copy.
@MainActor
@Observable
final class OnboardingFlow {
    enum Page: Hashable {
        case welcome
        case join
        case question(OnboardingStep)
        case stopped
        case togetherSince
        case catCoat
        case catName
        case invite
        case notifications
        case widget
    }

    static let doneKey = "onboardingDone"
    static let pageKey = "onboardingPage"
    static let joiningKey = "onboardingJoining"
    /// When the user agreed to the terms: either action on the welcome, under the line that says so. Kept for good.
    static let termsAcceptedKey = "onboardingTermsAcceptedAt"
    static let stoppedKey = "onboardingStopped"
    static let catalogueKey = "onboardingCatalogue"
    static let picksKey = "onboardingPicks"
    static let ageStep: OnboardingStepId = "age"
    static let underAge: OnboardingOptionId = "age-under-13"
    static let goalsStep: OnboardingStepId = "goals"
    static let widgetGoals: Set<OnboardingOptionId> = ["widgets", "stay-close"]
    static let catCoatStep: OnboardingStepId = "cat_coat"
    static let catNameStep: OnboardingStepId = "cat_name"
    static let inviteStep: OnboardingStepId = "invite_partner"
    static let inviteSent: OnboardingOptionId = "sent"

    /// The questions: the server's once `load()` has them, else the set this onboarding was saved with, else the
    /// bundled set. Decoded on first use, not at launch: most launches never show onboarding, and on the welcome
    /// `load()` decodes them off the main thread.
    var catalogue: OnboardingResponse {
        if let served { return served }
        if let decoded { return decoded }
        let value = Self.decodeCatalogue(saved: savedCatalogue, bundled: bundled)
        decoded = value
        return value
    }
    private var served: OnboardingResponse?
    @ObservationIgnored private var decoded: OnboardingResponse?
    @ObservationIgnored private let bundled: @Sendable () -> OnboardingResponse
    /// As saved when this flow was made; decoded with the bundled set, on first use.
    @ObservationIgnored private let savedCatalogue: Data?
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
    /// Joining with the partner's code instead of inviting them; the invite is theirs to do.
    private(set) var joining: Bool
    var joinCode = ""
    private(set) var stopped: Bool
    var togetherSince = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now

    @ObservationIgnored private let client: OnboardingClient
    @ObservationIgnored private let report: @Sendable ([ClientEvent]) async throws(TransportError) -> Void
    @ObservationIgnored private let queue: AnswerQueue
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let catNames: UserDefaults
    @ObservationIgnored private let canInvite: Bool
    @ObservationIgnored private let hasServer: Bool
    @ObservationIgnored private let asksTogetherSince: Bool
    @ObservationIgnored private let togetherSinceChosen: (Date) -> Void
    @ObservationIgnored private let requestPushes: () async -> Void
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
        hasServer: Bool = false,
        asksTogetherSince: Bool = false,
        togetherSinceChosen: @escaping (Date) -> Void = { _ in },
        requestPushes: @escaping () async -> Void = {},
        bundled: @escaping @Sendable () -> OnboardingResponse = { BundledOnboarding.load() },
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
        self.hasServer = hasServer
        self.asksTogetherSince = asksTogetherSince
        self.togetherSinceChosen = togetherSinceChosen
        self.requestPushes = requestPushes
        self.now = now
        self.bundled = bundled
        savedCatalogue = defaults.data(forKey: Self.catalogueKey)
        isFinished = defaults.bool(forKey: Self.doneKey)
        joining = defaults.bool(forKey: Self.joiningKey)
        stopped = defaults.bool(forKey: Self.stoppedKey)
        // A closed app opens again on the page it was on, with the questions and picks it had; `-onboardingPage 3`
        // opens that page, for screenshots.
        index = max(defaults.integer(forKey: Self.pageKey), 0)
        picks = Self.saved([OnboardingStepId: [OnboardingOptionId]].self, Self.picksKey, in: defaults) ?? [:]
        #if DEBUG
        // `-onboardingOpen catCoat` opens the coat step, for screenshots; `-catCoat <coat>` picks the coat it shows.
        if defaults.string(forKey: "onboardingOpen") == "catCoat", let coatPage = pages.firstIndex(of: .catCoat) {
            index = coatPage
        }
        #endif
    }

    var pages: [Page] {
        let goals = Set(picks[Self.goalsStep] ?? [])
        return [.welcome] + (joining ? [.join] : []) + catalogue.steps.map(Page.question)
            + (asksTogetherSince ? [.togetherSince] : []) + [.catCoat, .catName]
            + (canInvite && !joining ? [.invite] : []) + (hasServer ? [.notifications] : [])
            + (goals.isDisjoint(with: Self.widgetGoals) ? [] : [.widget])
    }

    /// The welcome is always the first page, so showing it needs no questions.
    var page: Page { stopped ? .stopped : index == 0 ? .welcome : pages[min(index, pages.count - 1)] }

    /// How far along the steps after the welcome, from 0 to 1.
    var progress: Double { Double(index) / Double(max(pages.count - 1, 1)) }

    /// The server's questions replace the bundled ones until the first question is shown; after that the person
    /// keeps the set they started with. Also sends whatever is still queued from an earlier launch.
    func load() async {
        if served == nil, decoded == nil {
            let saved = savedCatalogue, bundled = bundled
            let value = await Task.detached(priority: .userInitiated) {
                Self.decodeCatalogue(saved: saved, bundled: bundled)
            }.value
            if decoded == nil { decoded = value }
        }
        await send()
        guard let response = try? await client.fetch(), index == 0 else { return }
        served = response
    }

    private nonisolated static func decodeCatalogue(saved: Data?,
                                                    bundled: () -> OnboardingResponse) -> OnboardingResponse {
        saved.flatMap { try? JSONDecoder().decode(OnboardingResponse.self, from: $0) } ?? bundled()
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
        case .welcome, .join, .stopped, .togetherSince, .invite, .notifications, .widget:
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
        case .welcome, .stopped: nil
        case .join: "join_partner"
        case .question(let step): step.id
        case .togetherSince: "together_since"
        case .catCoat: Self.catCoatStep
        case .catName: Self.catNameStep
        case .invite: Self.inviteStep
        case .notifications: "notifications"
        case .widget: "widget_howto"
        }
    }

    var canSkip: Bool {
        switch page {
        case .welcome, .join, .stopped, .widget, .invite: false
        case .question(let step):
            switch step {
            case .single(let s), .multi(let s): s.skippable
            case .range(let s): s.skippable
            case .text(let s): s.skippable
            }
        case .togetherSince, .catCoat, .catName, .notifications: true
        }
    }

    // MARK: Moving

    func start() { advance() }

    /// "I have an invite code" on the welcome, or an invite link opened before onboarding was done.
    func join(code: String = "") {
        guard !isFinished, !stopped else { return }
        if page == .welcome { acceptTerms() }
        joining = true
        defaults.set(true, forKey: Self.joiningKey)
        if !code.isEmpty { joinCode = code }
        move(to: 1)
    }

    /// The partner is in: the joiner moves on from the code, the inviter from the invite.
    func partnerJoined() {
        switch page {
        case .join: advance()
        case .invite:
            invited = true
            continueTapped()
        default: break
        }
    }

    func continueTapped() {
        switch page {
        case .welcome:
            acceptTerms()
            advance()
        case .join, .widget:
            advance()
        case .stopped:
            break
        case .togetherSince:
            togetherSinceChosen(togetherSince)
            advance()
        case .notifications:
            let requestPushes = requestPushes
            Task { await requestPushes() }
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
        case .question(let step):
            guard let answer else { return }
            if step.id == Self.ageStep, answer == .single(option: Self.underAge) { return stop() }
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
        switch page {
        case .question, .catCoat, .catName, .invite: record(.skipped)
        case .welcome, .join, .stopped, .togetherSince, .notifications, .widget: break
        }
        advance()
    }

    var termsAccepted: Bool { defaults.object(forKey: Self.termsAcceptedKey) != nil }

    private func acceptTerms() {
        if !termsAccepted { defaults.set(Date.now, forKey: Self.termsAcceptedKey) }
    }

    func back() {
        guard index > 0, !stopped else { return }
        if page == .join {
            joining = false
            defaults.set(false, forKey: Self.joiningKey)
        }
        move(to: index - 1)
    }

    /// Under 13: the age answer is never sent, and onboarding stays on its last page.
    private func stop() {
        stopped = true
        defaults.set(true, forKey: Self.stoppedKey)
        events.append(ClientEvent(.ageGateStopped))
        Task { await send() }
    }

    private func move(to index: Int) {
        self.index = index
        defaults.set(index, forKey: Self.pageKey)
        defaults.set(try? JSONEncoder().encode(catalogue), forKey: Self.catalogueKey)
        defaults.set(try? JSONEncoder().encode(picks), forKey: Self.picksKey)
    }

    private static func saved<Value: Decodable>(_ type: Value.Type, _ key: String, in defaults: UserDefaults) -> Value? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
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
            move(to: index + 1)
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
