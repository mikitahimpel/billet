import SwiftUI

struct DatesScreen: View {
    let state: HomeState

    private enum Mode: String, CaseIterable {
        case swipe = "Swipe"
        case surprise = "Surprise us"
        case plans = "Plans"
    }

    @State private var mode: Mode = .swipe
    @State private var filter = DateFilter()

    @State private var matched: DateIdea?
    @State private var planner: PlannerTarget?

    @State private var surpriseIdea: DateIdea?
    @State private var shown: Set<Int> = []
    @State private var rerolls = 0
    @State private var rolling = false
    @State private var didRoll = false
    @State private var hatAngle: Double = 0

    private var us: UsStore { state.us }

    var body: some View {
        VStack(spacing: 0) {
            UsSheetHeader(title: "Date night", subtitle: "Swipe together, or let \(CatProfile.name()) pick")
            modeRow
            if mode != .plans { filterRow }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch mode {
                    case .swipe: swipeContent
                    case .surprise: surpriseContent
                    case .plans: plansContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .overlay { matchOverlay }
        .usSheet()
        .sheet(item: $planner) { target in
            DatePlannerSheet(state: state, target: target) { mode = .plans }
        }
    }

    // MARK: Swipe

    private var swipeContent: some View {
        let deck = us.deck(for: state.viewer, filter: filter)
        let matches = us.matches
        return VStack(alignment: .leading, spacing: 14) {
            Text("Swiping as \(state.viewer) · pass the phone to \(state.otherPartner) next")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.secondary)

            if deck.isEmpty {
                UsEmpty(icon: .init(symbol: "rectangle.stack.fill", tint: .lilac), title: "You've seen them all",
                        text: "Change the filters or check your matches.")
            } else {
                SwipeDeck(deck: deck, onSwipe: commitSwipe)
            }

            if !matches.isEmpty { matchesRow(matches) }
        }
    }

    private func matchesRow(_ matches: [DateIdea]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Matches")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.primary)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(matches) { idea in
                        Button {
                            planner = PlannerTarget(ideaID: idea.id)
                        } label: {
                            VStack(spacing: 6) {
                                UsIcon(glyph: idea.place.icon, size: 34)
                                Text(idea.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color(hex: 0x5B3A28))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .frame(width: 104, height: 92)
                            .background(Color(hex: 0xFFFBF3),
                                        in: .rect(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func commitSwipe(_ idea: DateIdea, liked: Bool) {
        let wasMatch = us.isMatch(idea.id)
        withAnimation(.snappy(duration: 0.25)) {
            us.swipe(idea.id, liked: liked, by: state.viewer)
            state.streak.record()
            if liked, !wasMatch, us.isMatch(idea.id) { matched = idea }
        }
    }

    @ViewBuilder
    private var matchOverlay: some View {
        if let idea = matched {
            DateMatchOverlay(idea: idea) {
                matched = nil
                planner = PlannerTarget(ideaID: idea.id)
            } onKeep: {
                withAnimation(.snappy(duration: 0.25)) { matched = nil }
            }
        }
    }

    // MARK: Surprise

    private var surpriseContent: some View {
        VStack(spacing: 14) {
            if let idea = surpriseIdea {
                DateIdeaCard(idea: idea)
                UsPrimaryButton(title: "Plan it") {
                    planner = PlannerTarget(ideaID: idea.id)
                }
                anotherButton
            } else {
                VStack(spacing: 16) {
                    UsIcon(glyph: .init(symbol: "wand.and.stars", tint: .lilac), size: 96)
                        .rotationEffect(.degrees(hatAngle), anchor: .bottom)
                    Text(surpriseCaption)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: 0x5B3A28).opacity(0.75))
                        .multilineTextAlignment(.center)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .background(Color(hex: 0xFFFBF3),
                            in: .rect(cornerRadius: 28, style: .continuous))

                UsPrimaryButton(title: "Surprise us", symbol: "dice") { roll() }
                    .opacity(rolling ? 0.6 : 1)
                    .disabled(rolling)
            }
        }
    }

    private var surpriseCaption: String {
        if rolling { return "\(CatProfile.name()) is digging…" }
        if didRoll { return "Nothing fits these filters" }
        return "\(CatProfile.name()) will pull a date out of the hat"
    }

    private var anotherButton: some View {
        Button(action: reroll) {
            Text(rerolls >= 3 ? "\(CatProfile.name()) is getting grumpy" : "Another one")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.white.opacity(0.1), in: .capsule)
                .overlay(Capsule().stroke(Ink.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func roll() {
        guard !rolling else { return }
        rolling = true
        withAnimation(.snappy(duration: 0.2)) { surpriseIdea = nil }
        withAnimation(.easeInOut(duration: 0.1).repeatCount(8, autoreverses: true)) {
            hatAngle = 12
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            let pick = us.randomIdea(filter: filter, excluding: shown)
            withAnimation(.snappy(duration: 0.3)) {
                hatAngle = 0
                surpriseIdea = pick
                if let pick { shown.insert(pick.id) }
                didRoll = true
                rolling = false
            }
        }
    }

    private func reroll() {
        guard surpriseIdea != nil, !rolling else { return }
        rerolls += 1
        roll()
    }

    // MARK: Plans

    @ViewBuilder
    private var plansContent: some View {
        if us.plannedSorted.isEmpty {
            UsEmpty(icon: .init(symbol: "calendar.badge.plus", tint: .sky), title: "No dates planned",
                    text: "Swipe or roll, then tap Plan it.")
        } else {
            VStack(spacing: 10) {
                ForEach(us.plannedSorted) { plan in
                    DatePlanCard(plan: plan,
                                 idea: DateIdea.idea(plan.ideaID),
                                 viewer: state.viewer,
                                 profile: state.profile,
                                 onEdit: { planner = PlannerTarget(ideaID: plan.ideaID, existing: plan) },
                                 onDelete: {
                                     withAnimation(.snappy(duration: 0.25)) { us.deletePlan(plan.id) }
                                 },
                                 onRate: { hearts in
                                     withAnimation(.snappy(duration: 0.25)) {
                                         us.rate(plan.id, hearts: hearts)
                                     }
                                 })
                }
            }
        }
    }

    // MARK: Shared controls

    private var modeRow: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases, id: \.self) { item in
                UsChip(title: item.rawValue, selected: mode == item) {
                    withAnimation(.snappy(duration: 0.25)) { mode = item }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var filterRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(DateIdea.Place.allCases, id: \.self) { place in
                    UsChip(title: place.displayTitle, selected: filter.places.contains(place)) {
                        toggle(place)
                    }
                }
                ForEach(DateIdea.Cost.allCases, id: \.self) { cost in
                    UsChip(title: cost.rawValue.capitalized, selected: filter.costs.contains(cost)) {
                        toggle(cost)
                    }
                }
                ForEach(DateIdea.Length.allCases, id: \.self) { length in
                    UsChip(title: length.rawValue.capitalized, selected: filter.lengths.contains(length)) {
                        toggle(length)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 10)
    }

    private func toggle(_ place: DateIdea.Place) {
        withAnimation(.snappy(duration: 0.2)) {
            if filter.places.contains(place) { filter.places.remove(place) } else { filter.places.insert(place) }
        }
    }

    private func toggle(_ cost: DateIdea.Cost) {
        withAnimation(.snappy(duration: 0.2)) {
            if filter.costs.contains(cost) { filter.costs.remove(cost) } else { filter.costs.insert(cost) }
        }
    }

    private func toggle(_ length: DateIdea.Length) {
        withAnimation(.snappy(duration: 0.2)) {
            if filter.lengths.contains(length) { filter.lengths.remove(length) } else { filter.lengths.insert(length) }
        }
    }
}

// MARK: - Pieces

private struct PlannerTarget: Identifiable, Hashable {
    let ideaID: Int
    var existing: PlannedDate?

    var id: String { existing.map(\.id.uuidString) ?? "new-\(ideaID)" }
}

/// Owns the drag so gesture frames redraw only the cards, not the screen that builds the deck.
private struct SwipeDeck: View {
    let deck: [DateIdea]
    var onSwipe: (DateIdea, Bool) -> Void

    @State private var drag: CGSize = .zero
    @State private var flying = false

    var body: some View {
        VStack(spacing: 14) {
            deckStack
            HStack(spacing: 28) {
                passButton
                likeButton
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var deckStack: some View {
        ZStack(alignment: .top) {
            ForEach(Array(deck.prefix(3).enumerated()).reversed(), id: \.element.id) { index, idea in
                stackedCard(idea, index: index)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 382)
    }

    @ViewBuilder
    private func stackedCard(_ idea: DateIdea, index: Int) -> some View {
        if index == 0 {
            DateIdeaCard(idea: idea)
                .overlay(alignment: .topLeading) {
                    stamp("LOVE", tint: Color(hex: 0xE287A9), strength: drag.width / 110)
                        .padding(24)
                }
                .overlay(alignment: .topTrailing) {
                    stamp("NOPE", tint: Color(hex: 0x5B3A28), strength: -drag.width / 110)
                        .padding(24)
                }
                .rotationEffect(.degrees(drag.width / 20))
                .offset(drag)
                .zIndex(3)
                .gesture(cardDrag)
        } else {
            DateIdeaCard(idea: idea)
                .scaleEffect(0.95)
                .offset(y: CGFloat(index) * 10)
                .zIndex(Double(3 - index))
        }
    }

    private func stamp(_ text: String, tint: Color, strength: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .heavy, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint, lineWidth: 3)
            )
            .rotationEffect(.degrees(text == "LOVE" ? -14 : 14))
            .opacity(Double(min(1, max(0, strength))))
    }

    private var passButton: some View {
        Button { fling(liked: false) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Ink.primary)
                .frame(width: 64, height: 64)
                .background(.white.opacity(0.1), in: .circle)
                .overlay(Circle().stroke(Ink.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pass")
    }

    private var likeButton: some View {
        Button { fling(liked: true) } label: {
            Image(systemName: "heart.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Circle().fill(.honeyGradient))
                .shadow(color: Color.honeyDeep.opacity(0.4), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Love")
    }

    private var cardDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !flying else { return }
                drag = value.translation
            }
            .onEnded { value in
                guard !flying else { return }
                if abs(value.translation.width) > 110 {
                    fling(liked: value.translation.width > 0)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { drag = .zero }
                }
            }
    }

    private func fling(liked: Bool) {
        guard !flying, !deck.isEmpty else { return }
        flying = true
        withAnimation(.easeIn(duration: 0.18)) {
            drag = CGSize(width: liked ? 640 : -640, height: drag.height)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.18))
            commitSwipe(liked: liked)
        }
    }

    private func commitSwipe(liked: Bool) {
        defer {
            flying = false
            drag = .zero
        }
        guard let idea = deck.first else { return }
        onSwipe(idea, liked)
    }
}

private struct DateIdeaCard: View {
    let idea: DateIdea

    var body: some View {
        VStack(spacing: 12) {
            UsIcon(glyph: idea.place.icon, size: 72)
            Text(idea.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x5B3A28))
                .multilineTextAlignment(.center)
            Text(idea.pitch)
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: 0x5B3A28).opacity(0.75))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                tag(idea.place.displayTitle)
                tag(idea.cost.rawValue.capitalized)
                tag(idea.time.rawValue.capitalized)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .background(Color(hex: 0xFFFBF3), in: .rect(cornerRadius: 28, style: .continuous))
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(hex: 0x5B3A28))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(hex: 0xF0DCC0), in: .capsule)
    }
}

private struct DateMatchOverlay: View {
    let idea: DateIdea
    var onPlan: () -> Void
    var onKeep: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Text("It's a match!")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x5B3A28))
                UsIcon(glyph: .init(symbol: "heart.fill", tint: .blush), size: 72)
                Text(idea.title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x5B3A28))
                    .multilineTextAlignment(.center)
                Label("+10", systemImage: "star.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.honeyDeep)

                HStack(spacing: 10) {
                    Button(action: onKeep) {
                        Text("Keep swiping")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(hex: 0x5B3A28))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color(hex: 0xF0DCC0), in: .capsule)
                    }
                    .buttonStyle(.plain)

                    Button(action: onPlan) {
                        Text("Plan it")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Capsule().fill(.honeyGradient))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
            .padding(24)
            .frame(maxWidth: 330)
            .background(Color(hex: 0xFFFBF3), in: .rect(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        }
    }
}

private struct DatePlanCard: View {
    let plan: PlannedDate
    let idea: DateIdea?
    let viewer: String
    let profile: CoupleStore
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onRate: (Int) -> Void

    private var hidden: Bool { plan.surprise && plan.organizer != viewer }
    private var upcoming: Bool { plan.rating == nil && plan.date > .now }

    var body: some View {
        Group {
            if upcoming {
                content.contextMenu {
                    Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                }
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                UsIcon(glyph: hidden ? .init(symbol: "gift.fill", tint: .coral)
                                     : idea?.place.icon ?? .init(symbol: "heart.fill", tint: .blush), size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hidden ? "Surprise from \(plan.organizer)" : idea?.title ?? "Date")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Ink.primary)
                    Text(plan.date.formatted(.dateTime.weekday().day().month().hour().minute()))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.secondary)
                }
                Spacer(minLength: 0)
                Monogram(partner: plan.organizer, profile: profile, size: 26)
            }

            if hidden {
                if !plan.hint.isEmpty {
                    Text("Hint: \(plan.hint)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.secondary)
                }
            } else if !plan.place.isEmpty {
                Label(plan.place, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.secondary)
            }

            ratingRow
        }
        .padding(14)
        .usCard(radius: 22)
    }

    @ViewBuilder
    private var ratingRow: some View {
        if let rating = plan.rating {
            HStack(spacing: 4) {
                ForEach(1...3, id: \.self) { value in
                    Image(systemName: value <= rating ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.blushPink.opacity(value <= rating ? 1 : 0.4))
                }
                Spacer(minLength: 0)
            }
        } else if plan.date < .now {
            HStack(spacing: 8) {
                Text("How was it?")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.secondary)
                ForEach(1...3, id: \.self) { value in
                    Button { onRate(value) } label: {
                        Image(systemName: "heart")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.blushPink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value) hearts")
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct DatePlannerSheet: View {
    let state: HomeState
    let ideaID: Int
    let existing: PlannedDate?
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var place: String
    @State private var organizer: String
    @State private var surprise: Bool
    @State private var hint: String

    init(state: HomeState, target: PlannerTarget, onSaved: @escaping () -> Void) {
        self.state = state
        self.ideaID = target.ideaID
        self.existing = target.existing
        self.onSaved = onSaved
        _date = State(initialValue: target.existing?.date ?? Date.now.addingTimeInterval(86_400))
        _place = State(initialValue: target.existing?.place ?? "")
        _organizer = State(initialValue: target.existing?.organizer ?? state.viewer)
        _surprise = State(initialValue: target.existing?.surprise ?? false)
        _hint = State(initialValue: target.existing?.hint ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            UsSheetHeader(title: DateIdea.idea(ideaID)?.title ?? "Plan a date",
                          subtitle: "Pick a day and what you'll do")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DatePicker("When", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .tint(.honey)
                        .colorScheme(.dark)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Ink.primary)
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .usCard(radius: 16)

                    UsField(placeholder: "Place, e.g. our kitchen", text: $place)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Who plans it")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Ink.secondary)
                        HStack(spacing: 8) {
                            ForEach([state.partners.0, state.partners.1], id: \.self) { initial in
                                UsChip(title: initial, selected: organizer == initial) {
                                    organizer = initial
                                }
                            }
                        }
                    }

                    Toggle("Surprise mode", isOn: $surprise)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Ink.primary)
                        .tint(.honey)
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .usCard(radius: 16)

                    if surprise {
                        UsField(placeholder: "Hint, e.g. dress warm", text: $hint)
                    }

                    UsPrimaryButton(title: "Save date") { save() }
                        .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .usSheet(detents: [.medium, .large])
    }

    private func save() {
        state.us.upsertPlan(PlannedDate(
            id: existing?.id ?? UUID(),
            ideaID: ideaID,
            date: date,
            place: place.trimmingCharacters(in: .whitespacesAndNewlines),
            organizer: organizer,
            surprise: surprise,
            hint: hint.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        onSaved()
        dismiss()
    }
}

private extension DateIdea.Place {
    var displayTitle: String { rawValue.capitalized }
}
