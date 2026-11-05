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
    @State private var filtersOpen = false

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
            if mode != .plans { filterBar }
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
        .sheet(isPresented: $filtersOpen) {
            DateFilterSheet(filter: $filter, count: fitting)
        }
    }

    /// Swipe counts what's left in this partner's deck, Surprise everything in season.
    private func fitting(_ filter: DateFilter) -> Int {
        switch mode {
        case .swipe: us.deck(for: state.viewer, filter: filter).count
        case .surprise, .plans: DateIdea.all.filter { filter.allows($0) && $0.inSeason(.current) }.count
        }
    }

    // MARK: Swipe

    private var swipeContent: some View {
        let deck = us.deck(for: state.viewer, filter: filter)
        let matches = us.matches
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Monogram(partner: state.viewer, profile: state.profile, size: 22)
                Text("\(state.profile.name(of: state.viewer))'s turn, then \(state.profile.name(of: state.otherPartner))")
                    .font(.nookiCaption.weight(.semibold))
                    .foregroundStyle(Ink.textSecondary)
            }

            if deck.isEmpty {
                UsEmpty(icon: .init(symbol: "rectangle.stack.fill", tint: .lilac), title: "That's the whole deck",
                        text: filter.isEmpty ? "Plan one of your matches." : "Loosen a filter for more.")
            } else {
                SwipeDeck(deck: deck, onSwipe: commitSwipe)
            }

            if !matches.isEmpty { matchesRow(matches) }
        }
    }

    private func matchesRow(_ matches: [DateIdea]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Matches")
                .font(.nookiHeadline)
                .foregroundStyle(Ink.text)
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

                UsPrimaryButton(title: "Surprise us", symbol: "dice") { roll() }
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
        Button(action: reroll) {
            Text(rerolls >= 3 ? "\(CatProfile.name()) is getting grumpy" : "Another one")
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

    /// The Filters button, then the active filters to remove one by one, or quick picks while none is set.
    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                filtersButton
                if filter.isEmpty {
                    ForEach(DatePreset.all) { preset in
                        UsChip(title: preset.title, selected: false) {
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
                RoundedRectangle(cornerRadius: Radius.tag, style: .continuous)
                    .stroke(tint, lineWidth: 3)
            )
            .rotationEffect(.degrees(text == "LOVE" ? -14 : 14))
            .opacity(Double(min(1, max(0, strength))))
    }

    private var passButton: some View {
        Button { fling(liked: false) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 22, weight: .bold))
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
                .font(.system(size: 24, weight: .bold))
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
    static let height: CGFloat = 420

    let idea: DateIdea

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
        DateScenePicture(art: idea.art)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(idea.title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
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
                                       .init(color: Ink.sheet.opacity(0.88), location: 1)],
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
        VStack(spacing: 0) {
            UsSheetHeader(title: "Filters", subtitle: fits == 1 ? "1 idea fits" : "\(fits) ideas fit") {
                if !filter.isEmpty {
                    Button("Reset") {
                        withAnimation(.snappy(duration: 0.2)) { filter = DateFilter() }
                    }
                    .font(.nookiHeadline)
                    .foregroundStyle(Color.honey)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    group("Quick picks") {
                        HStack(spacing: 8) {
                            ForEach(DatePreset.all) { preset in
                                UsChip(title: preset.title, selected: filter == preset.filter) {
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

            UsPrimaryButton(title: fits == 0 ? "Nothing fits" : "Show \(fits) ideas") { dismiss() }
                .disabled(fits == 0)
                .opacity(fits == 0 ? 0.5 : 1)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .usSheet(detents: [.large])
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
                        .font(.nookiHeadline)
                        .foregroundStyle(Ink.text)
                    Text(plan.date.formatted(.dateTime.weekday().day().month().hour().minute()))
                        .font(.nookiCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
                Spacer(minLength: 0)
                Monogram(partner: plan.organizer, profile: profile, size: 26)
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
        .usCard(radius: 22)
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
            HStack(spacing: 8) {
                Text("How was it?")
                    .font(.nookiCaption.weight(.semibold))
                    .foregroundStyle(Ink.textSecondary)
                ForEach(1...3, id: \.self) { value in
                    Button { onRate(value) } label: {
                        Image(systemName: "heart")
                            .font(.nookiHeadline)
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
                        .font(.nookiBody)
                        .foregroundStyle(Ink.text)
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .usCard(radius: 16)

                    UsField(placeholder: "Place, e.g. our kitchen", text: $place)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Who plans it")
                            .font(.nookiCaption.weight(.semibold))
                            .foregroundStyle(Ink.textSecondary)
                        HStack(spacing: 8) {
                            ForEach([state.partners.0, state.partners.1], id: \.self) { initial in
                                UsChip(title: initial, selected: organizer == initial) {
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
