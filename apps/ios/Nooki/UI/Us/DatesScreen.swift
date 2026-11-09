import PhotosUI
import SwiftUI
import Design

struct DatesScreen: View {
    let state: HomeState

    private enum Mode: String, CaseIterable {
        case swipe = "Swipe"
        case dates = "Our dates"
        case surprise = "Surprise us"
    }

    @State private var mode: Mode = .swipe
    @State private var filter = DateFilter()
    @State private var filtersOpen = false

    @State private var matched: DateIdea?
    @State private var planner: PlannerTarget?
    @State private var finishing: PlannedDate?
    /// The idea just liked without a match yet, for a short line under the deck.
    @State private var likedAlone: Int?

    @State private var surpriseIdea: DateIdea?
    @State private var shown: Set<Int> = []
    @State private var rerolls = 0
    @State private var rolling = false
    @State private var didRoll = false
    @State private var hatAngle: Double = 0

    private var us: UsStore { state.us }

    var body: some View {
        BilletSheet("Date night", scrolls: false) {
        VStack(spacing: 0) {
            SheetSubtitle(text: "Swipe together, or let \(CatProfile.name()) pick")
                .padding(.horizontal, Space.gutter)
            modeRow
            if mode != .dates { filterBar }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch mode {
                    case .swipe: swipeContent
                    case .dates: datesContent
                    case .surprise: surpriseContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .overlay { matchOverlay }
        }
        .sheet(item: $planner) { target in
            DatePlannerSheet(state: state, target: target) { mode = .dates }
        }
        .sheet(item: $finishing) { plan in
            DateDoneSheet(state: state, plan: plan)
        }
        .sheet(isPresented: $filtersOpen) {
            DateFilterSheet(filter: $filter, count: fitting)
        }
    }

    /// Swipe counts what's left in this partner's deck, Surprise everything in season.
    private func fitting(_ filter: DateFilter) -> Int {
        switch mode {
        case .swipe: us.deck(for: state.viewer, filter: filter).count
        case .surprise, .dates: DateIdea.all.filter { filter.allows($0) && $0.inSeason(.current) }.count
        }
    }

    // MARK: Swipe

    private var swipeContent: some View {
        let deck = us.deck(for: state.viewer, filter: filter)
        let partner = state.profile.name(of: state.otherPartner)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Monogram(partner: state.viewer, profile: state.profile, size: 22)
                Text(likedAlone != nil
                     ? "Saved. If \(partner) loves it too, it's a match"
                     : deck.first.map { us.isSecondLook($0.id, for: state.viewer) } == true
                     ? "Another look at the ones you skipped"
                     : "\(state.profile.name(of: state.viewer))'s turn, then \(partner)")
                    .font(.nookiCaption.weight(.semibold))
                    .foregroundStyle(Ink.textSecondary)
                    .contentTransition(.opacity)
            }
            .task(id: likedAlone) {
                guard likedAlone != nil else { return }
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.easeOut(duration: 0.3)) { likedAlone = nil }
            }

            if deck.isEmpty {
                deckEnd
            } else {
                SwipeDeck(deck: deck, onSwipe: commitSwipe)
            }
        }
    }

    /// What to do once this partner has liked every card that fits; skipped ones come back in the deck.
    private var deckEnd: some View {
        let toPlan = us.matches.count
        let partner = state.profile.name(of: state.otherPartner)
        let partnerLeft = us.unseenCount(for: state.otherPartner, filter: filter)
        let text = if partnerLeft > 0 {
            "\(partner) has \(partnerLeft) left to swipe. New matches land in Our dates."
        } else if filter.isEmpty {
            "You've liked every idea. Plan your matches or surprise each other."
        } else {
            "Loosen a filter for more."
        }
        return VStack(spacing: 12) {
            EmptyState(icon: .init(symbol: "rectangle.stack.fill", tint: .lilac), title: "That's the whole deck",
                       text: text)
            if toPlan > 0 {
                PrimaryButton(toPlan == 1 ? "Plan your match" : "Plan one of \(toPlan) matches") {
                    withAnimation(.snappy(duration: 0.25)) { mode = .dates }
                }
            }
            secondaryButton("Surprise us") {
                withAnimation(.snappy(duration: 0.25)) { mode = .surprise }
            }
            if !filter.isEmpty {
                secondaryButton("Clear filters") {
                    withAnimation(.snappy(duration: 0.2)) { filter = DateFilter() }
                }
            }
        }
    }

    private func matchesRow(_ matches: [DateIdea]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("To plan", caption: "You both loved these")
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(matches) { idea in
                        Button {
                            planner = PlannerTarget(ideaID: idea.id)
                        } label: {
                            DateScenePicture(art: idea.art)
                                .overlay(alignment: .bottomLeading) {
                                    Text(idea.title)
                                        .font(.nookiMicro)
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .padding(8)
                                }
                                .frame(width: 104, height: 124)
                                .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func commitSwipe(_ idea: DateIdea, liked: Bool) {
        // SwipeDeck calls this inside its own hand-off animation.
        let wasMatch = us.isMatch(idea.id)
        us.swipe(idea.id, liked: liked, by: state.viewer)
        state.streak.record()
        guard liked else { return }
        if !wasMatch, us.isMatch(idea.id) {
            matched = idea
        } else {
            likedAlone = idea.id
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
                PrimaryButton("Plan it") {
                    planner = PlannerTarget(ideaID: idea.id)
                }
                anotherButton
            } else {
                VStack(spacing: 16) {
                    UsIcon(glyph: .init(symbol: "wand.and.stars", tint: .lilac), size: 72)
                        .rotationEffect(.degrees(hatAngle), anchor: .bottom)
                    Text(surpriseCaption)
                        .font(.nookiHeadline)
                        .foregroundStyle(Ink.text)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
                .frame(height: DateIdeaCard.height, alignment: .bottom)
                .background { DateScenePicture() }
                .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))

                PrimaryButton("Surprise us", symbol: "dice") { roll() }
                    .opacity(rolling ? 0.6 : 1)
                    .disabled(rolling)
            }
        }
    }

    private var surpriseCaption: String {
        if rolling { return "\(CatProfile.name()) is digging…" }
        if didRoll { return "Nothing fits. Loosen a filter." }
        return "\(CatProfile.name()) will pull a date out of the hat"
    }

    private var anotherButton: some View {
        secondaryButton(rerolls >= 3 ? "\(CatProfile.name()) is getting grumpy" : "Another one", action: reroll)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.nookiHeadline)
                .foregroundStyle(Ink.text)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Ink.surfaceRaised, in: .capsule)
                .overlay(Capsule().stroke(Ink.separator, lineWidth: 0.5))
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

    // MARK: Our dates

    /// Matches to plan, then planned dates, then the ones done: the path every liked idea takes.
    @ViewBuilder
    private var datesContent: some View {
        let toPlan = us.matches, comingUp = us.comingUp, done = us.done
        if toPlan.isEmpty, comingUp.isEmpty, done.isEmpty {
            VStack(spacing: 12) {
                EmptyState(icon: .init(symbol: "heart.text.square.fill", tint: .blush), title: "No dates yet",
                           text: "Swipe together. When you both love an idea, it lands here.")
                PrimaryButton("Start swiping") {
                    withAnimation(.snappy(duration: 0.25)) { mode = .swipe }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                if !toPlan.isEmpty { matchesRow(toPlan) }
                if !comingUp.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionTitle("Coming up")
                        ForEach(comingUp) { planCard($0) }
                    }
                }
                if !done.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionTitle("Done", caption: done.count == 1 ? "1 date" : "\(done.count) dates")
                        ForEach(done) { planCard($0) }
                    }
                }
            }
        }
    }

    private func planCard(_ plan: PlannedDate) -> some View {
        DatePlanCard(plan: plan,
                     idea: DateIdea.idea(plan.ideaID),
                     viewer: state.viewer,
                     profile: state.profile,
                     moments: state.moments,
                     onEdit: { planner = PlannerTarget(ideaID: plan.ideaID, existing: plan) },
                     onDelete: {
                         DateReminders.cancel(plan.id)
                         withAnimation(.snappy(duration: 0.25)) { us.deletePlan(plan.id) }
                     },
                     onDone: { finishing = plan })
    }

    private func sectionTitle(_ title: String, caption: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.nookiHeadline)
                .foregroundStyle(Ink.text)
            Spacer(minLength: 0)
            if let caption {
                Text(caption)
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
        }
    }

    // MARK: Shared controls

    private var modeRow: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases, id: \.self) { item in
                let waiting = item == .dates ? us.matches.count : 0
                FilterChip(waiting > 0 ? "\(item.rawValue) · \(waiting)" : item.rawValue, isSelected: mode == item) {
                    withAnimation(.snappy(duration: 0.25)) { mode = item }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    /// The Filters button, then the active filters to remove one by one, or quick picks while none is set.
    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                filtersButton
                if filter.isEmpty {
                    ForEach(DatePreset.all) { preset in
                        FilterChip(preset.title, isSelected: false) {
                            withAnimation(.snappy(duration: 0.2)) { filter = preset.filter }
                        }
                    }
                } else {
                    ForEach(filter.tags, id: \.self) { tag in
                        removableChip(tag)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 10)
    }

    private var filtersButton: some View {
        Button { filtersOpen = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.nookiCaption.weight(.semibold))
                Text("Filters")
                if !filter.isEmpty {
                    Text("\(filter.tags.count)")
                        .font(.nookiMicro)
                        .foregroundStyle(Ink.heroInk)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Circle().fill(.honeyGradient))
                }
            }
            .font(.nookiCallout.weight(.semibold))
            .foregroundStyle(Ink.text)
            .padding(.leading, 14)
            .padding(.trailing, filter.isEmpty ? 14 : 7)
            .frame(height: 34)
            .background(Ink.surfaceRaised, in: .capsule)
            .overlay(Capsule().stroke(Ink.separator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.isEmpty ? "Filters" : "Filters, \(filter.tags.count) on")
    }

    private func removableChip(_ tag: DateFilter.Tag) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { filter.toggle(tag) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tag.symbol)
                    .font(.nookiMicro)
                Text(tag.title)
                Image(systemName: "xmark")
                    .font(.nookiMicro)
                    .foregroundStyle(Ink.textSecondary)
            }
            .font(.nookiCallout.weight(.semibold))
            .foregroundStyle(Ink.text)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.honey.opacity(0.32), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(tag.title)")
    }
}

// MARK: - Pieces

struct PlannerTarget: Identifiable, Hashable {
    let ideaID: Int
    var existing: PlannedDate?

    var id: String { existing.map(\.id.uuidString) ?? "new-\(ideaID)" }
}
