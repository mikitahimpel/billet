import Design
import OurioShared
import SwiftUI
import Transport
import Wire

struct PickTonightScreen: View {
    let state: HomeState
    let list: UsList
    let details: WatchDetails

    @Environment(ServerSession.self) private var session: ServerSession?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: PickTonightModel?
    @State private var drag = CGSize.zero

    private var partnerName: String { state.profile.name(of: state.profile.couple.other) }

    var body: some View {
        ZStack {
            BilletSheet("Pick tonight", scrolls: false) {
                VStack(spacing: 0) {
                    if let subtitle {
                        SheetSubtitle(text: subtitle)
                            .padding(.horizontal, Space.gutter)
                    }
                    content
                }
            }
            if let model, let match = model.match {
                let note = model.matchByPartner
                    ? "\(partnerName) just swiped ♥ too"
                    : "\(partnerName) got a notification too"
                PickMatchScreen(match: match, note: note, plan: { plan(match) }, keep: {
                    withAnimation(.snappy(duration: 0.25)) { model.dismissMatch() }
                })
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .animation(.snappy(duration: 0.3), value: model?.match)
        .onChange(of: model?.match) { _, match in
            if match != nil { report(.pickTonightMatched) }
        }
        .task { await start() }
        .onDisappear { session?.matches = nil }
    }

    private var subtitle: String? {
        guard let model, !model.loading else { return nil }
        if model.offline { return "Offline · \(partnerName) won't see these swipes" }
        return model.partnerPicked == 0
            ? "\(partnerName) hasn't picked yet"
            : "\(partnerName) picked \(model.partnerPicked) · your turn"
    }

    @ViewBuilder
    private var content: some View {
        if let model, !(model.loading && model.deck.isEmpty) {
            if model.deck.isEmpty {
                EmptyState(icon: .init(symbol: "popcorn.fill", tint: .coral), title: "That's every card",
                        text: "Add more to To watch, or come back once \(partnerName) has picked.")
                    .frame(maxHeight: .infinity)
            } else {
                deck(model)
            }
        } else {
            ProgressView().frame(maxHeight: .infinity)
        }
    }

    private func deck(_ model: PickTonightModel) -> some View {
        VStack(spacing: Space.l) {
            ZStack {
                if model.deck.count > 1 {
                    card(model.deck[1])
                        .rotationEffect(.degrees(5))
                        .scaleEffect(0.94)
                        .opacity(0.7)
                        .accessibilityHidden(true)
                }
                if let top = model.deck.first {
                    card(top)
                        .id(top.id)
                        .offset(drag)
                        .rotationEffect(.degrees(Double(drag.width / 18)))
                        .gesture(swipeGesture(top, model))
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                }
            }
            .padding(.horizontal, 44)
            .frame(maxHeight: .infinity)

            if let top = model.deck.first {
                HStack(spacing: 28) {
                    round("xmark", label: "Not tonight", honey: false) { swipe(top, .pass, model) }
                    round("eye.fill", label: "Seen it", honey: false) { swipe(top, .seen, model) }
                    round("heart.fill", label: "Want to", honey: true) { swipe(top, .want, model) }
                }
                Text(model.unsent ? "That swipe didn't send. Try it again." : "Not tonight · Seen it · Want to")
                    .font(.ourioCaption)
                    .foregroundStyle(model.unsent ? Ink.accentText : Ink.textSecondary)
            }
        }
        .padding(.top, Space.l)
        .padding(.bottom, Space.xl)
    }

    private func card(_ card: PickCard) -> some View {
        PosterImage(path: card.media?.posterPath, title: card.name, size: .card, showsTitle: false)
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(card.name)
                        .ourioScaledFont(size: 26, weight: .bold, design: .rounded, relativeTo: .title)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                    Text(caption(card))
                        .font(.ourioCallout)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                }
                .padding(Space.l)
            }
            .corners(.card)
            .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(card.name), \(caption(card))")
    }

    /// "2016 · 1 h 56 min · Netflix" when the list has the details, else the year and whose card it is.
    private func caption(_ card: PickCard) -> String {
        var parts: [String] = []
        if let media = card.media, let info = details.details(of: media) {
            if let year = info.summary.year { parts.append(String(year)) }
            if let runtime = info.summary.runtime { parts.append(TitleCaption.minutes(runtime)) }
            if let seasons = info.summary.seasons { parts.append(seasons == 1 ? "1 season" : "\(seasons) seasons") }
            if let service = info.watch.stream.first { parts.append(service.name) }
        } else if let media = card.media {
            if let year = media.year { parts.append(String(year)) }
            parts.append(TitleCaption.kind(media.wireKind))
        }
        parts.append(card.itemID == nil ? "Suggested" : "On your list")
        return parts.joined(separator: " · ")
    }

    private func round(_ symbol: String, label: String, honey: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .ourioScaledFont(size: 24, weight: .bold)
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .foregroundStyle(honey ? Ink.heroInk : Ink.text)
                .frame(width: 64, height: 64)
                .background(Circle().fill(honey ? AnyShapeStyle(.honeyGradient) : AnyShapeStyle(Ink.surfaceRaised)))
                .shadow(color: .black.opacity(honey ? 0.2 : 0.08), radius: 8, y: 4)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }

    private func swipeGesture(_ card: PickCard, _ model: PickTonightModel) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let width = value.translation.width
                if abs(width) > 110 {
                    swipe(card, width > 0 ? .want : .pass, model)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { drag = .zero }
                }
            }
    }

    private func swipe(_ card: PickCard, _ choice: PickChoice, _ model: PickTonightModel) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.82)) {
            model.take(card)
            drag = .zero
        }
        apply(card, choice)
        Task { await model.send(card, choice) }
    }

    /// What the swipe does to the list: 👁 moves it to Watched, ♥ marks it wanted.
    private func apply(_ card: PickCard, _ choice: PickChoice) {
        switch choice {
        case .pass:
            break
        case .seen:
            if let itemID = card.itemID {
                state.us.setItem(itemID, in: list.id, done: true, by: state.viewer)
            } else if let media = card.media {
                state.us.addItem(card.name, to: list.id, author: state.viewer, media: media)
                let added = state.us.list(list.id)?.items.first { $0.media?.tmdb == media.tmdb && $0.media?.kind == media.kind }
                if let added { state.us.setItem(added.id, in: list.id, done: true, by: state.viewer) }
            }
        case .want:
            if let itemID = card.itemID { state.us.setWant(itemID, in: list.id, wants: true, by: state.viewer) }
        }
    }

    private func start() async {
        guard model == nil, let sync = session?.pickTonight else { return }
        let model = PickTonightModel(sync: sync, titles: session?.titles)
        self.model = model
        session?.matches = { model.received($0) }
        report(.pickTonightOpened)
        await model.load(list, partners: state.profile.couple.partners)
    }

    /// Plans tonight's movie night in Date night, which counts for the streak, and opens it.
    private func plan(_ match: PickMatch) {
        let idea = 1
        let plan = PlannedDate(ideaID: idea, date: Self.tonight(), place: match.name, organizer: state.viewer,
                               remind: true)
        state.us.upsertPlan(plan)
        state.streak.record()
        let title = DateIdea.idea(idea)?.title ?? "Movie night"
        let organizer = state.profile.name(of: state.viewer)
        Task { await DateReminders.schedule(plan, title: title, organizer: organizer) }
        report(.pickTonightPlanned)
        model?.dismissMatch()
        dismiss()
        // The list's sheet gives way to Date night once this screen has closed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { state.usRoute = .dates }
    }

    /// 8 pm today, or the next half hour once it is past 7:30.
    static func tonight(now: Date = .now, calendar: Calendar = .current) -> Date {
        let eight = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
        guard now > eight.addingTimeInterval(-30 * 60) else { return eight }
        let minutes = calendar.component(.minute, from: now)
        let next = calendar.date(byAdding: .minute, value: minutes < 30 ? 30 - minutes : 60 - minutes, to: now) ?? now
        return calendar.date(bySetting: .second, value: 0, of: next) ?? next
    }

    private func report(_ name: ClientEventName) {
        guard let api = session?.api else { return }
        Task { try? await api.reportEvents([ClientEvent(name)]) }
    }
}

private struct PickMatchScreen: View {
    let match: PickMatch
    /// Who else knows: the partner got a push, or the partner's swipe made the match.
    let note: String
    var plan: () -> Void
    var keep: () -> Void

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x6E4630), Color(hex: 0x2A1A12)], center: .top, startRadius: 40,
                           endRadius: 620)
                .ignoresSafeArea()
            VStack(spacing: Space.m) {
                Spacer(minLength: 0)
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let image = UIImage(named: CatCoat.current().avatar) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "cat.fill").font(.system(size: 44)).foregroundStyle(Color.honey)
                        }
                    }
                    .frame(width: 92, height: 92)
                    .background(Circle().fill(Ink.surface))
                    .clipShape(.circle)
                    Text("🍿")
                        .font(.system(size: 38))
                        .offset(x: 14, y: 6)
                }
                .accessibilityHidden(true)
                Text("It's a match!")
                    .font(.ourioLargeTitle)
                    .foregroundStyle(Ink.primary)
                Text("You both want to watch")
                    .font(.ourioCallout)
                    .foregroundStyle(Ink.secondary)
                PosterImage(path: match.posterPath, title: match.name, size: .card)
                    .frame(width: 150, height: 225)
                    .corners(.inner)
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                    .padding(.vertical, Space.s)
                Text(match.name)
                    .font(.ourioTitle)
                    .foregroundStyle(Ink.primary)
                    .multilineTextAlignment(.center)
                Text(note)
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.secondary)
                Spacer(minLength: 0)
                VStack(spacing: Space.s) {
                    PrimaryButton("We're watching it tonight", action: plan)
                    Button("Keep swiping", action: keep)
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.l)
        }
        .environment(\.colorScheme, .dark)
    }
}
