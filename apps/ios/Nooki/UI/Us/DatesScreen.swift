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
                .clipShape(.rect(cornerRadius: Radius.hero, style: .continuous))

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let flingDistance: CGFloat = 110

    /// 0 at rest, 1 once the top card is dragged far enough to fling; the cards behind rise with it.
    private var progress: CGFloat { min(1, abs(drag.width) / Self.flingDistance) }

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
        .frame(height: DateIdeaCard.height + 22)
    }

    /// One view path for every position, so a card keeps its identity (and its drawn picture) while it moves from
    /// the back of the stack to the top; an if/else here would rebuild it with a crossfade.
    private func stackedCard(_ idea: DateIdea, index: Int) -> some View {
        let top = index == 0
        // Each card behind moves one step forward as the top one is dragged away.
        let depth = top ? 0 : CGFloat(index) - progress
        return DateIdeaCard(idea: idea)
            .overlay(alignment: .topLeading) {
                stamp("LOVE", tint: Color(hex: 0xE287A9), strength: top ? drag.width / Self.flingDistance : 0)
                    .padding(24)
            }
            .overlay(alignment: .topTrailing) {
                stamp("NOPE", tint: Color(hex: 0x5B3A28), strength: top ? -drag.width / Self.flingDistance : 0)
                    .padding(24)
            }
            .scaleEffect(reduceMotion ? 1 : 1 - depth * 0.05, anchor: .bottom)
            .offset(y: reduceMotion ? 0 : depth * 12)
            .rotationEffect(.degrees(top && !reduceMotion ? drag.width / 20 : 0))
            .offset(top ? drag : .zero)
            .zIndex(Double(3 - index))
            // A flung card is already off screen when it leaves; with Reduce Motion it fades where it is.
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity, removal: .identity))
            .gesture(cardDrag, including: top ? .all : .subviews)
    }

    private func stamp(_ text: String, tint: Color, strength: CGFloat) -> some View {
        Text(text)
            .font(.system(.title, design: .rounded, weight: .heavy))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.tag, style: .continuous)
                    .stroke(tint, lineWidth: 3)
            )
            .rotationEffect(.degrees(text == "LOVE" ? -14 : 14))
            .opacity(Double(min(1, max(0, strength))))
    }

    private var passButton: some View {
        Button { fling(liked: false) } label: {
            Image(systemName: "xmark")
                .font(.system(.title2, weight: .bold))
                .foregroundStyle(Ink.text)
                .frame(width: 64, height: 64)
                .background(Ink.surfaceRaised, in: .circle)
                .overlay(Circle().stroke(Ink.separator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pass")
    }

    private var likeButton: some View {
        Button { fling(liked: true) } label: {
            Image(systemName: "heart.fill")
                .font(.system(.title2, weight: .bold))
                .foregroundStyle(Ink.heroInk)
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
                // A quick flick counts as well as a long drag.
                let throwWidth = value.predictedEndTranslation.width
                if abs(value.translation.width) > Self.flingDistance || abs(throwWidth) > Self.flingDistance * 2.5 {
                    fling(liked: throwWidth > 0)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { drag = .zero }
                }
            }
    }

    private func fling(liked: Bool) {
        guard !flying, !deck.isEmpty else { return }
        flying = true
        if reduceMotion {
            commitSwipe(liked: liked)
            return
        }
        // The cards behind finish rising during the throw, so the hand-off below lands on the same frame.
        withAnimation(.easeIn(duration: 0.2)) {
            drag = CGSize(width: liked ? 640 : -640, height: drag.height + 40)
        } completion: {
            commitSwipe(liked: liked)
        }
    }

    private func commitSwipe(liked: Bool) {
        guard let idea = deck.first else {
            flying = false
            return
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.82)) {
            onSwipe(idea, liked)
            drag = .zero
            flying = false
        }
    }
}

private struct DateIdeaCard: View {
    static let height: CGFloat = 420

    let idea: DateIdea

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
        DateScenePicture(art: idea.art)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(idea.title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(idea.pitch)
                        .font(.nookiCallout)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        tag(idea.place.title, symbol: idea.place.icon.symbol)
                        tag(idea.cost.title, symbol: idea.cost.symbol)
                        tag(idea.time.title, symbol: idea.time.symbol)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .clipShape(shape)
            .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
            .accessibilityElement(children: .combine)
    }

    private func tag(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.nookiMicro)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.18), in: .capsule)
    }
}

/// A date scene filling its frame, darkened at the bottom so white text on it stays readable.
private struct DateScenePicture: View {
    /// An idea's picture, fetched from the server; nil for the Plans backdrop, which ships with the app.
    var art: DateIdea.Art?

    /// The pictures are immutable, so `URLCache` keeps them across launches. A build without a server shows only
    /// each picture's colour.
    private static let host = Backend.baseURL(host: Bundle.main.object(forInfoDictionaryKey: Backend.infoKey) as? String)

    var body: some View {
        Color(hex: art.flatMap { UInt32($0.color.dropFirst(), radix: 16) } ?? 0x6B4A35)
            .overlay {
                if let art {
                    AsyncImage(url: Self.host?.appending(path: art.path),
                               transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        phase.image?.resizable().scaledToFill()
                    }
                } else {
                    Image(decorative: "DateScene-plans")
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.35),
                                       .init(color: Ink.screen.opacity(0.88), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipped()
    }
}

private struct DatePreset: Identifiable {
    let title: String
    let filter: DateFilter

    var id: String { title }

    static let all = [
        DatePreset(title: "Night in", filter: DateFilter(places: [.home], lengths: [.hour, .evening])),
        DatePreset(title: "Free", filter: DateFilter(costs: [.free])),
        DatePreset(title: "Long distance", filter: DateFilter(places: [.apart])),
    ]
}

private struct DateFilterSheet: View {
    @Binding var filter: DateFilter
    let count: (DateFilter) -> Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let fits = count(filter)
        BilletSheet("Filters", scrolls: false) {
        VStack(spacing: 0) {
            SheetSubtitle(text: fits == 1 ? "1 idea fits" : "\(fits) ideas fit")
                .padding(.horizontal, Space.gutter)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    group("Quick picks") {
                        HStack(spacing: 8) {
                            ForEach(DatePreset.all) { preset in
                                FilterChip(preset.title, isSelected: filter == preset.filter) {
                                    withAnimation(.snappy(duration: 0.2)) { filter = preset.filter }
                                }
                            }
                        }
                    }
                    group("Where") {
                        options(DateIdea.Place.allCases.map(DateFilter.Tag.place), columns: 2)
                    }
                    group("Budget") {
                        options(DateIdea.Cost.allCases.map(DateFilter.Tag.cost), columns: 3)
                    }
                    group("Time") {
                        options(DateIdea.Length.allCases.map(DateFilter.Tag.length), columns: 3)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            PrimaryButton(fits == 0 ? "Nothing fits" : "Show \(fits) ideas") { dismiss() }
                .disabled(fits == 0)
                .opacity(fits == 0 ? 0.5 : 1)
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.m)
        }
        }
        .toolbar {
            if !filter.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { withAnimation(.snappy(duration: 0.2)) { filter = DateFilter() } }
                }
            }
        }
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.nookiHeadline)
                .foregroundStyle(Ink.textSecondary)
            content()
        }
    }

    private func options(_ tags: [DateFilter.Tag], columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                option(tag)
            }
        }
    }

    private func option(_ tag: DateFilter.Tag) -> some View {
        let selected = filter.contains(tag)
        return Button {
            withAnimation(.snappy(duration: 0.2)) { filter.toggle(tag) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tag.symbol)
                    .font(.nookiHeadline)
                    .foregroundStyle(selected ? Color.honey : Ink.textSecondary)
                Text(tag.title)
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(selected ? Color.honey.opacity(0.22) : Ink.surface,
                        in: .rect(cornerRadius: Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .stroke(selected ? Color.honey : Ink.separator, lineWidth: selected ? 1.5 : 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                    .font(.nookiLargeTitle)
                    .foregroundStyle(Ink.text)
                UsIcon(glyph: .init(symbol: "heart.fill", tint: .blush), size: 72)
                Text(idea.title)
                    .font(.nookiTitle)
                    .foregroundStyle(Ink.text)
                    .multilineTextAlignment(.center)
                Label("+10", systemImage: "star.fill")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.accentText)

                HStack(spacing: 10) {
                    Button(action: onKeep) {
                        Text("Keep swiping")
                            .font(.nookiHeadline)
                            .foregroundStyle(Ink.text)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(Ink.surfaceRaised, in: .capsule)
                    }
                    .buttonStyle(.plain)

                    Button(action: onPlan) {
                        Text("Plan it")
                            .font(.nookiHeadline)
                            .foregroundStyle(Ink.heroInk)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(.honeyGradient))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
            .padding(24)
            .frame(maxWidth: 330)
            .background(Ink.surface, in: .rect(cornerRadius: Radius.hero, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        }
    }
}

private struct DatePlanCard: View {
    let plan: PlannedDate
    let idea: DateIdea?
    let viewer: String
    let profile: CoupleStore
    let moments: MomentStore
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onDone: () -> Void

    @State private var photo: UIImage?

    private var hidden: Bool { plan.surprise && plan.organizer != viewer && plan.rating == nil }
    private var upcoming: Bool { plan.rating == nil && plan.date > .now }
    private var moment: Moment? { plan.momentID.flatMap { id in moments.moments.first { $0.id == id } } }

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
                        .font(.nookiHeadline)
                        .foregroundStyle(Ink.text)
                    HStack(spacing: 4) {
                        Text(plan.date.formatted(.dateTime.weekday().day().month().hour().minute()))
                        if upcoming, plan.remind == true {
                            Image(systemName: "bell.fill")
                                .accessibilityLabel("Reminder on")
                        }
                    }
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
                }
                Spacer(minLength: 0)
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 42, height: 42)
                        .clipShape(.rect(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)
                } else {
                    Monogram(partner: plan.organizer, profile: profile, size: 26)
                }
            }
            .task(id: plan.momentID) {
                guard let moment else { return }
                photo = moments.cachedThumbnail(for: moment, maxPixels: 128)
                if photo == nil { photo = await moments.thumbnail(for: moment, maxPixels: 128) }
            }

            if hidden {
                if !plan.hint.isEmpty {
                    Text("Hint: \(plan.hint)")
                        .font(.nookiCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
            } else if !plan.place.isEmpty {
                Label(plan.place, systemImage: "mappin.and.ellipse")
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
            }

            ratingRow
        }
        .padding(14)
        .cardSurface(radius: 22)
    }

    @ViewBuilder
    private var ratingRow: some View {
        if let rating = plan.rating {
            HStack(spacing: 4) {
                ForEach(1...3, id: \.self) { value in
                    Image(systemName: value <= rating ? "heart.fill" : "heart")
                        .font(.nookiHeadline)
                        .foregroundStyle(Color.blushPink.opacity(value <= rating ? 1 : 0.4))
                }
                Spacer(minLength: 0)
            }
        } else if plan.date < .now {
            Button(action: onDone) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("How was it? Mark it done")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.nookiCaption.weight(.bold))
                }
                .font(.nookiCallout.weight(.semibold))
                .foregroundStyle(Color.honey)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(Color.honey.opacity(0.16), in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Closes a date: hearts, and a photo from it that goes into Moments (and to the partner, as any new moment does).
private struct DateDoneSheet: View {
    let state: HomeState
    let plan: PlannedDate

    @Environment(\.dismiss) private var dismiss
    @State private var hearts = 3
    @State private var pick: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var caption: String

    init(state: HomeState, plan: PlannedDate) {
        self.state = state
        self.plan = plan
        _caption = State(initialValue: DateIdea.idea(plan.ideaID)?.title ?? "Date night")
    }

    var body: some View {
        BilletSheet("How was it?") {
                VStack(spacing: 14) {
                    if let title = DateIdea.idea(plan.ideaID)?.title { SheetSubtitle(text: title) }
                    HStack(spacing: 18) {
                        ForEach(1...3, id: \.self) { value in
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { hearts = value }
                            } label: {
                                Image(systemName: value <= hearts ? "heart.fill" : "heart")
                                    .font(.system(.largeTitle, weight: .semibold))
                                    .foregroundStyle(Color.blushPink)
                                    .symbolEffect(.bounce, value: hearts == value)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(value == 1 ? "1 heart" : "\(value) hearts")
                            .accessibilityAddTraits(value == hearts ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    PhotosPicker(selection: $pick, matching: .images) {
                        photoSlot
                    }
                    .buttonStyle(.plain)

                    if photo != nil {
                        UsField(placeholder: "Caption", text: $caption)
                    }

                    PrimaryButton(photo == nil ? "Done" : "Done, add to Moments") { save() }
                        .padding(.top, 4)
                }
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let image = await item.loadImage(maxPixels: MomentStore.storedPixels) {
                    withAnimation(.snappy(duration: 0.25)) { photo = image }
                }
            }
        }
    }

    @ViewBuilder
    private var photoSlot: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Label("Change", systemImage: "photo")
                        .font(.nookiCaption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: .capsule)
                        .padding(10)
                }
                .accessibilityLabel("Change photo")
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(.title, weight: .semibold))
                    .foregroundStyle(Color.honey)
                Text("Add a photo from the date")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                Text("It goes into your Moments")
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .cardSurface()
        }
    }

    private func save() {
        var momentID: UUID?
        if let photo {
            let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            // addMoment puts the newest photo first.
            if state.journal.addMoment(photo, caption: text, shares: true) {
                momentID = state.moments.moments.first?.id
            }
        }
        state.us.rate(plan.id, hearts: hearts, momentID: momentID)
        DateReminders.cancel(plan.id)
        dismiss()
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
    @State private var remind: Bool

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
        _remind = State(initialValue: target.existing?.remind ?? (target.existing == nil))
    }

    var body: some View {
        BilletSheet(DateIdea.idea(ideaID)?.title ?? "Plan a date", size: .mediumLarge, onConfirm: { save() }) {
                VStack(alignment: .leading, spacing: 12) {
                    SheetSubtitle(text: "Pick a day and what you'll do")
                    DatePicker("When", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .tint(.honey)
                        .font(.nookiBody)
                        .foregroundStyle(Ink.text)
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .cardSurface(radius: Radius.control)

                    UsField(placeholder: "Place, e.g. our kitchen", text: $place)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Who plans it")
                            .font(.nookiCaption.weight(.semibold))
                            .foregroundStyle(Ink.textSecondary)
                        HStack(spacing: 8) {
                            ForEach([state.partners.0, state.partners.1], id: \.self) { initial in
                                FilterChip(initial, isSelected: organizer == initial) {
                                    organizer = initial
                                }
                            }
                        }
                    }

                    Toggle("Surprise mode", isOn: $surprise)
                        .font(.nookiBody)
                        .foregroundStyle(Ink.text)
                        .tint(.honey)
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .cardSurface(radius: Radius.control)

                    if surprise {
                        UsField(placeholder: "Hint, e.g. dress warm", text: $hint)
                    }

                    Toggle("Remind us a day and an hour before", isOn: $remind)
                        .font(.nookiBody)
                        .foregroundStyle(Ink.text)
                        .tint(.honey)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        .cardSurface(radius: Radius.control)

                }
        }
    }

    private func save() {
        let plan = PlannedDate(
            id: existing?.id ?? UUID(),
            ideaID: ideaID,
            date: date,
            place: place.trimmingCharacters(in: .whitespacesAndNewlines),
            organizer: organizer,
            surprise: surprise,
            hint: hint.trimmingCharacters(in: .whitespacesAndNewlines),
            remind: remind
        )
        state.us.upsertPlan(plan)
        let title = DateIdea.idea(ideaID)?.title ?? "Date night"
        let organizerName = state.profile.name(of: organizer)
        Task { await DateReminders.schedule(plan, title: title, organizer: organizerName) }
        onSaved()
        dismiss()
    }
}

private extension DateIdea.Place {
    var title: String {
        switch self {
        case .home: "At home"
        case .city: "In town"
        case .nature: "Outdoors"
        case .apart: "Long distance"
        }
    }
}

private extension DateIdea.Cost {
    var title: String {
        switch self {
        case .free: "Free"
        case .cheap: "Cheap"
        case .nice: "Treat"
        }
    }

    var symbol: String {
        switch self {
        case .free: "heart.fill"
        case .cheap: "dollarsign.circle.fill"
        case .nice: "sparkles"
        }
    }
}

private extension DateIdea.Length {
    var title: String {
        switch self {
        case .hour: "1 hour"
        case .evening: "Evening"
        case .day: "All day"
        }
    }

    var symbol: String {
        switch self {
        case .hour: "clock.fill"
        case .evening: "moon.stars.fill"
        case .day: "sun.max.fill"
        }
    }
}

private extension DateFilter {
    enum Tag: Hashable {
        case place(DateIdea.Place)
        case cost(DateIdea.Cost)
        case length(DateIdea.Length)

        var title: String {
            switch self {
            case .place(let place): place.title
            case .cost(let cost): cost.title
            case .length(let length): length.title
            }
        }

        var symbol: String {
            switch self {
            case .place(let place): place.icon.symbol
            case .cost(let cost): cost.symbol
            case .length(let length): length.symbol
            }
        }
    }

    var isEmpty: Bool { places.isEmpty && costs.isEmpty && lengths.isEmpty }

    /// In the sheet's order, so the chips above the deck don't jump around.
    var tags: [Tag] {
        DateIdea.Place.allCases.filter(places.contains).map(Tag.place)
            + DateIdea.Cost.allCases.filter(costs.contains).map(Tag.cost)
            + DateIdea.Length.allCases.filter(lengths.contains).map(Tag.length)
    }

    func contains(_ tag: Tag) -> Bool {
        switch tag {
        case .place(let place): places.contains(place)
        case .cost(let cost): costs.contains(cost)
        case .length(let length): lengths.contains(length)
        }
    }

    mutating func toggle(_ tag: Tag) {
        switch tag {
        case .place(let place): if places.remove(place) == nil { places.insert(place) }
        case .cost(let cost): if costs.remove(cost) == nil { costs.insert(cost) }
        case .length(let length): if lengths.remove(length) == nil { lengths.insert(length) }
        }
    }
}
