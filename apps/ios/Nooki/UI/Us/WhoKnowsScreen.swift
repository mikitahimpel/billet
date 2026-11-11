import MomentsInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import Design
import UsInterface
import Wire

struct WhoKnowsScreen: View {
    let state: HomeState
    let model: WhoKnowsModel

    @Environment(ServerSession.self) private var session: ServerSession?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The round whose intro this phone has shown, so the host greets once a day.
    @AppStorage("whoKnows.introRound") private var introRound = ""
    @State private var tapped = 0

    private var partner: String { state.profile.name(of: state.otherPartner) }
    private var subject: String { model.isSubject ? state.viewer : state.otherPartner }

    var body: some View {
        BilletSheet("Who knows who", scrolls: false) {
            VStack(spacing: 0) {
                if let subtitle {
                    SheetSubtitle(text: subtitle)
                        .padding(.horizontal, Space.gutter)
                }
                content
                    .frame(maxHeight: .infinity)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: tapped)
        .task { await refresh() }
    }

    private func refresh() async {
        await model.load()
        if model.lacksQuestions { await session?.refreshGuessCatalog() }
    }

    /// The partner's progress while the round is still hidden.
    private var subtitle: String? {
        switch model.phase {
        case .answerAboutYou, .guessAboutPartner, .waitingForPartner:
            "\(partner) answered \(model.partnerAnswered) of \(model.total)"
        case .revealed: "Today's results"
        case .offline: "Offline"
        case .loading, .unpaired: nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .unpaired:
            EmptyState(icon: UsGlyph(symbol: "person.2.fill", tint: .honey), title: "Pair up to play",
                    text: "Who knows who takes two: one of you answers five questions about yourself, the other guesses.")
        case .offline:
            VStack(spacing: Space.l) {
                EmptyState(icon: UsGlyph(symbol: "wifi.slash", tint: .sky), title: "Can't reach today's round",
                        text: "Answers stay hidden in your room on the server, so the game needs a connection.")
                RetryButton { Task { await model.load() } }
            }
        case .answerAboutYou, .guessAboutPartner:
            if let round = model.response?.round, model.answers.isEmpty, introRound != round.id {
                intro(round)
            } else if let question = model.current {
                ask(question)
            } else if model.lacksQuestions {
                // The catalog refresh failed or came back without today's questions.
                VStack(spacing: Space.l) {
                    EmptyState(icon: UsGlyph(symbol: "questionmark.bubble.fill", tint: .honey),
                            title: "Can't load today's questions",
                            text: "Check your connection and try again.")
                    RetryButton { Task { await refresh() } }
                }
            } else {
                ProgressView()
            }
        case .waitingForPartner:
            waiting
        case .revealed:
            VStack(spacing: Space.m) {
                if model.lacksQuestions {
                    VStack(spacing: Space.s) {
                        ErrorLine("Some questions didn't load.")
                        RetryButton(compact: true) { Task { await refresh() } }
                    }
                    .padding(.top, Space.s)
                }
                WhoKnowsReveal(state: state, model: model, openDates: openDates)
            }
        }
    }

    // MARK: Intro

    private func intro(_ round: GuessRound) -> some View {
        FillingScroll {
            WhoKnowsArt(name: "WhoKnows-host", size: 200)
            Text(model.isSubject ? "Today's round is about you" : "Today's round is about \(partner)")
                .font(.ourioTitle)
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)
            Text(model.isSubject
                 ? "Answer \(model.total) questions about yourself. \(partner) guesses, and neither of you sees a thing until you're both done."
                 : "Guess how \(partner) answers \(model.total) questions. Nobody sees a thing until you're both done.")
                .font(.ourioCallout)
                .foregroundStyle(Ink.textSecondary)
                .multilineTextAlignment(.center)
        } bottom: {
            PrimaryButton("Let's go") {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .snappy(duration: 0.3)) { introRound = round.id }
            }
        }
    }

    // MARK: Question

    private func ask(_ question: GuessQuestion) -> some View {
        let number = model.answers.count + 1
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                WhoKnowsProgress(done: model.answers.count, total: model.total)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Question \(number) of \(model.total)")
                HStack(spacing: Space.s) {
                    Monogram(partner: subject, profile: state.profile, size: 28)
                        .accessibilityHidden(true)
                    Text(model.isSubject ? "About you" : "About \(partner)")
                        .font(.ourioCallout)
                        .foregroundStyle(Ink.textSecondary)
                }
                Text(WhoKnowsModel.text(question, isSubject: model.isSubject, subjectName: partner))
                    .font(.ourioTitle)
                    .foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: Space.m) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                        Button { pick(index) } label: { WhoKnowsOption(letter: index, text: option) }
                            .buttonStyle(PressScaleStyle())
                            .accessibilityLabel(option)
                            .accessibilityHint(model.isSubject ? "Locks your answer" : "Locks your guess")
                    }
                }
                if model.unsent {
                    Text("That answer didn't send. Pick it again.")
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.accentText)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.l)
            .id(question.id)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                               removal: .move(edge: .leading).combined(with: .opacity)))
        }
        .ourioScrollEdges()
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .snappy(duration: 0.3), value: question.id)
    }

    private func pick(_ option: Int) {
        tapped += 1
        Task { await model.answer(option) }
    }

    // MARK: Waiting

    private var waiting: some View {
        FillingScroll {
            WhoKnowsArt(name: "WhoKnows-waiting", size: 200)
            Text("Waiting for \(partner)")
                .font(.ourioTitle)
                .foregroundStyle(Ink.text)
            Text("You're done. The answers open for you both once \(partner) has answered all \(model.total).")
                .font(.ourioCallout)
                .foregroundStyle(Ink.textSecondary)
                .multilineTextAlignment(.center)
            WhoKnowsProgress(done: model.partnerAnswered, total: model.total)
                .frame(maxWidth: 220)
                .padding(.top, Space.s)
                .accessibilityHidden(true)
            Text("\(partner) answered \(model.partnerAnswered) of \(model.total)")
                .font(.ourioCaption.monospacedDigit())
                .foregroundStyle(Ink.textSecondary)
                .contentTransition(.numericText())
                .animation(.snappy, value: model.partnerAnswered)
        } bottom: {
            EmptyView()
        }
    }

    /// Date night, once this sheet has closed.
    private func openDates() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { state.usRoute = .dates }
    }
}

// MARK: - Reveal

private struct WhoKnowsReveal: View {
    let state: HomeState
    let model: WhoKnowsModel
    var openDates: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0

    private var me: String { state.profile.name(of: state.viewer) }
    private var partner: String { state.profile.name(of: state.otherPartner) }

    var body: some View {
        let reveal = model.reveal
        VStack(spacing: Space.l) {
            if step < reveal.count {
                ScrollView {
                    WhoKnowsRevealStep(state: state, model: model, item: reveal[step], index: step, total: reveal.count)
                        .id(step)
                        .transition(reduceMotion ? .opacity : .push(from: .trailing))
                }
                .ourioScrollEdges()
                PrimaryButton(step + 1 < reveal.count ? "Next" : "See the score") { advance() }
            } else {
                ScrollView { summary }.ourioScrollEdges()
                PrimaryButton("See them again") { withAnimation(animation) { step = 0 } }
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.l)
        .padding(.bottom, Space.l)
    }

    private var animation: Animation { reduceMotion ? .easeOut(duration: 0.2) : .snappy(duration: 0.3) }

    private func advance() {
        withAnimation(animation) { step += 1 }
    }

    private var summary: some View {
        VStack(spacing: Space.l) {
            Text(model.isSubject ? "\(partner) got \(model.hits) of \(model.total) about you"
                                 : "You got \(model.hits) of \(model.total) about \(partner)")
                .font(.ourioTitle)
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            if let week = model.score?.week {
                VStack(spacing: Space.s) {
                    Text("This week")
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.textSecondary)
                    HStack(alignment: .center, spacing: Space.l) {
                        tally(me, week.mine, leads: week.mine > week.partner)
                        Text("·").font(.ourioTitle).foregroundStyle(Ink.textTertiary)
                        tally(partner, week.partner, leads: week.partner > week.mine)
                    }
                    Text(WhoKnowsModel.stake(week, partner: partner))
                        .font(.ourioCallout)
                        .foregroundStyle(Ink.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Open Date night", action: openDates)
                        .buttonStyle(SecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(CardMetrics.padding)
                .cardSurface(warm: true)
                .accessibilityElement(children: .contain)
            }

            HStack(spacing: Space.m) {
                Image(systemName: "sparkles")
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.accentText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("+\(model.coinsEarned) coins")
                        .font(.ourioHeadline.monospacedDigit())
                        .foregroundStyle(Ink.text)
                    Text("\(WhoKnowsModel.roundCoins) for playing, \(WhoKnowsModel.hitCoins) for each right guess")
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(CardMetrics.padding)
            .cardSurface()
            .accessibilityElement(children: .combine)
        }
    }

    private func tally(_ name: String, _ points: Int, leads: Bool) -> some View {
        VStack(spacing: Space.xs) {
            ZStack {
                if leads { WhoKnowsArt(name: "WhoKnows-trophy", size: 56) }
            }
            .frame(height: 56)
            Text("\(points)")
                .font(.ourioLargeTitleDigits)
                .foregroundStyle(Ink.text)
            Text(name)
                .font(.ourioCallout)
                .foregroundStyle(Ink.textSecondary)
        }
        .frame(minWidth: 88)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(points) \(points == 1 ? "point" : "points")\(leads ? ", leads the week" : "")")
    }
}

private struct WhoKnowsRevealStep: View {
    let state: HomeState
    let model: WhoKnowsModel
    let item: GuessReveal
    let index: Int
    let total: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false

    private var partner: String { state.profile.name(of: state.otherPartner) }

    var body: some View {
        let question = model.question(item.question)
        let options = question?.options ?? []
        VStack(spacing: Space.l) {
            Text("Question \(index + 1) of \(total)")
                .font(.ourioCaption)
                .foregroundStyle(Ink.textSecondary)
            if let question {
                Text(WhoKnowsModel.text(question, isSubject: model.isSubject, subjectName: partner))
                    .font(.ourioTitle)
                    .foregroundStyle(Ink.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ZStack(alignment: .topTrailing) {
                WhoKnowsArt(name: item.hit ? "WhoKnows-hit" : "WhoKnows-miss", size: 160)
                if item.hit {
                    Text("+\(WhoKnowsModel.hitCoins)")
                        .font(.ourioHeadline.monospacedDigit())
                        .foregroundStyle(Ink.heroInk)
                        .padding(.horizontal, Space.m)
                        .padding(.vertical, Space.xs)
                        .background(Capsule().fill(Color.honey))
                        .accessibilityHidden(true)
                }
            }
            .scaleEffect(popped || reduceMotion ? 1 : 0.6)
            .opacity(popped ? 1 : 0)
            Text(item.hit ? "Right!" : "Not quite")
                .font(.ourioTitle)
                .foregroundStyle(Ink.text)
            VStack(spacing: Space.m) {
                if item.hit {
                    row(options, item.truth, label: "\(answerLabel) · \(guessLabel)", mark: .hit)
                } else {
                    row(options, item.guess, label: guessLabel, mark: .miss)
                    row(options, item.truth, label: answerLabel, mark: .truth)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.6)) {
                popped = true
            }
        }
        .sensoryFeedback(item.hit ? .success : .impact(weight: .light), trigger: popped)
    }

    private var answerLabel: String { model.isSubject ? "Your answer" : "\(partner)'s answer" }
    private var guessLabel: String { model.isSubject ? "\(partner)'s guess" : "Your guess" }

    private enum Mark { case hit, miss, truth }

    private func row(_ options: [String], _ option: Int, label: String, mark: Mark) -> some View {
        let text = options.indices.contains(option) ? options[option] : "Option \(option + 1)"
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        let symbol = switch mark {
        case .hit: "checkmark.circle.fill"
        case .miss: "xmark.circle.fill"
        case .truth: "star.circle.fill"
        }
        let tint: Color = switch mark {
        case .hit, .truth: .honey
        case .miss: .blushPink
        }
        return HStack(spacing: Space.m) {
            Image(systemName: symbol)
                .font(.ourioTitle)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textSecondary)
                Text(text)
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.text)
                    .strikethrough(mark == .miss, color: .blushPink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(Ink.surface)
            if mark == .hit { shape.fill(Color.honey.opacity(0.18)) }
        }
        .overlay {
            switch mark {
            case .hit, .truth: shape.strokeBorder(Color.honey, lineWidth: 2)
            case .miss: shape.strokeBorder(Color.blushPink.opacity(0.6), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(text)\(mark == .miss ? ", wrong" : mark == .hit ? ", right" : "")")
    }
}

// MARK: - Pieces

private struct WhoKnowsProgress: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: Space.s) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index < done ? AnyShapeStyle(Color.honey) : AnyShapeStyle(Ink.surfaceRaised))
                    .frame(height: 6)
            }
        }
        .animation(.snappy(duration: 0.25), value: done)
    }
}

private struct WhoKnowsOption: View {
    let letter: Int
    let text: String
    @ScaledMetric(relativeTo: .headline) private var disc: CGFloat = 32

    var body: some View {
        HStack(spacing: Space.m) {
            Text(String(UnicodeScalar(UInt8(65 + letter))))
                .font(.ourioHeadline)
                .foregroundStyle(Ink.accentText)
                .frame(width: disc, height: disc)
                .background(Circle().fill(Ink.surfaceRaised))
                .accessibilityHidden(true)
            Text(text)
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .cardSurface(radius: Radius.control)
        .contentShape(.rect(cornerRadius: Radius.control))
    }
}

/// Centred in the sheet while it fits, scrolling when the words outgrow it, as at the largest text sizes; `bottom`
/// stays under the scroll.
private struct FillingScroll<Content: View, Bottom: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var bottom: Bottom
    @State private var height: CGFloat = 0

    var body: some View {
        VStack(spacing: Space.m) {
            ScrollView {
                VStack(spacing: Space.m) { content }
                    .padding(.horizontal, Space.gutter)
                    .frame(maxWidth: .infinity, minHeight: height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .ourioScrollEdges()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            bottom
                .padding(.horizontal, Space.gutter)
        }
        .padding(.bottom, Space.l)
    }
}

struct WhoKnowsArt: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
