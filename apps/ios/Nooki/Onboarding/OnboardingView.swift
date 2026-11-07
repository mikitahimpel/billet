import FeaturePairing
import SwiftUI
import Design
import Wire

/// The first launch as a native flow on the app's warm screen: a welcome, then one step per page with a large title,
/// a progress bar, Back and Skip in the bar, the choices as inset-grouped rows and one primary button at the bottom.
/// Server questions are drawn by their kind, so a new question needs no app update. Built on the adaptive tokens;
/// the app is dark for now, and light comes app-wide in one step.
struct OnboardingView: View {
    @Bindable var flow: OnboardingFlow
    /// The invite comes from the pairing on the server; nil in a build without one.
    let pairing: PairingModel?
    /// The invite needs the account; until the sign-in finishes the page waits for it.
    var signedIn = false
    /// Where invite links point: the server, which hands `/i/<code>` to the app.
    var inviteBase: URL?
    /// The account already has a partner, as when the pairing finished while the app was closed.
    var alreadyPaired = false
    /// The pairing finished, on either side.
    var paired: () -> Void = {}
    /// Dev server only: pairs with a bot partner instead of waiting for a real one; nil elsewhere.
    var demoPartner: (() -> Void)?

    let language = Locale.current.language.languageCode?.identifier

    var body: some View {
        NavigationStack {
            page
                .id(flow.index)
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
                    .combined(with: .opacity))
                // The step's title is drawn in the page as a large rounded title, so a long question wraps instead of
                // being cut off the way a navigation bar's large title is.
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden()
                .toolbar { toolbar }
                .safeAreaInset(edge: .bottom) { bottomBar }
                .background(Ink.screen.ignoresSafeArea())
        }
        .tint(Ink.accentText)
        .animation(.smooth(duration: 0.35), value: flow.index)
        .sensoryFeedback(.selection, trigger: flow.picks)
        .haptic(.selection, trigger: flow.coat)
        .task { await flow.load() }
        .onChange(of: flow.index, initial: true) { flow.appeared() }
        .task(id: [flow.page == .invite, signedIn]) {
            guard flow.page == .invite, signedIn, let pairing, case .choosing(nil, _) = pairing.state else { return }
            pairing.createInvite()
        }
        .onChange(of: isPaired || alreadyPaired, initial: true) { _, joined in
            guard joined else { return }
            flow.partnerJoined()
            if isPaired { paired() }
        }
    }

    private var isPaired: Bool {
        if case .paired = pairing?.state { true } else { false }
    }

    var title: String {
        switch flow.page {
        case .welcome: ""
        case .join: String(localized: "Enter your invite code")
        case .question(let step): step.title.text(for: language)
        case .stopped: String(localized: "See you in a few years")
        case .togetherSince: String(localized: "When did your story start?")
        case .catCoat: String(localized: "Choose your cat")
        case .catName: String(localized: "Name your cat")
        case .invite: String(localized: "Invite your partner")
        case .notifications: String(localized: "Don't miss a drawing")
        case .widget: String(localized: "Keep \(CatProfile.name()) on your Home Screen")
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if flow.page != .welcome, flow.page != .stopped {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left") { flow.back() }
            }
            ToolbarItem(placement: .principal) {
                ProgressView(value: flow.progress)
                    .frame(width: 120)
                    .accessibilityLabel("Step \(flow.index) of \(flow.pages.count - 1)")
            }
            if flow.canSkip {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { flow.skip() }
                }
            }
        }
    }

    // MARK: Pages

    @ViewBuilder private var page: some View {
        switch flow.page {
        case .welcome: welcome
        case .join: join
        case .question(let step): question(step)
        case .stopped: stopped
        case .togetherSince: togetherSince
        case .catCoat: catCoat
        case .catName: catName
        case .invite: invite
        case .notifications: notifications
        case .widget: widget
        }
    }

    /// The hero fills the top, the rest sits under it, and the whole page centers in the space above the button;
    /// it scrolls only when large text doesn't fit.
    private var welcome: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Space.l) {
                    CatStage(coat: flow.coat, height: min(proxy.size.height * 0.5, 400))
                        .accessibilityHidden(true)
                        .padding(.bottom, Space.s)
                    Text("A cat for the two of you")
                        .font(.nookiLargeTitle)
                        .foregroundStyle(Ink.text)
                        .multilineTextAlignment(.center)
                    Text("A few quick questions first. At the end you pick its coat and give it a name.")
                        .font(.nookiBody)
                        .foregroundStyle(Ink.textSecondary)
                        .multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: Space.m) {
                        welcomePoint("pawprint.fill", "Feed it, pet it and play with it together")
                        welcomePoint("scribble.variable", "Send each other drawings and notes")
                        welcomePoint("flame.fill", "Keep a streak going, day after day")
                    }
                    .padding(.top, Space.s)
                    if pairing != nil {
                        Button("I have an invite code") { flow.join() }
                            .font(.nookiBody.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Space.gutter)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func welcomePoint(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
                .font(.nookiCallout)
                .foregroundStyle(Ink.text)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Ink.accentText)
                .frame(width: 24)
        }
    }

    @ViewBuilder private func question(_ step: OnboardingStep) -> some View {
        switch step {
        case .single(let choice), .multi(let choice):
            form(subtitle: choice.subtitle?.text(for: language)) {
                GroupedSection(inset: Space.l) {
                    ForEach(choice.options, id: \.id) { option in
                        optionRow(option, multi: step.isMulti,
                                  picked: flow.picks[choice.id]?.contains(option.id) ?? false) {
                            flow.toggle(option, in: step)
                        }
                    }
                }
            }
        case .range(let range):
            form(subtitle: range.subtitle?.text(for: language)) {
                GroupedSection(inset: Space.l) {
                    Picker(range.title.text(for: language), selection: rangeBinding(range)) {
                        ForEach(Array(stride(from: range.min, through: range.max, by: range.step)), id: \.self) { value in
                            Text(range.unit.map { "\(value) \($0.text(for: language))" } ?? "\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .rowCell()
                }
            }
        case .text(let field):
            form(subtitle: field.subtitle?.text(for: language)) {
                GroupedSection(inset: Space.l) {
                    TextField(field.placeholder?.text(for: language) ?? "", text: textBinding(field))
                        .font(.nookiBody)
                        .submitLabel(.done)
                        .rowCell()
                }
            }
        }
    }

    private var catCoat: some View {
        // The cat takes the height the title, her name and the chips leave; when they leave too little (large text),
        // the page scrolls with a smaller cat.
        ViewThatFits(in: .vertical) {
            coatPage(stage: nil)
            ScrollView { coatPage(stage: 200) }
                .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func coatPage(stage: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            PageTitle(title)
                .padding(.horizontal, Space.gutter)
            CoatPicker(coat: $flow.coat, stageHeight: stage)
        }
        .padding(.top, Space.l)
        .padding(.bottom, Space.s)
    }

    private static let nameIdeas = ["Mochi", "Tofu", "Biscuit", "Pumpkin", "Luna", "Miso"]

    private var catName: some View {
        form(say: "What should we call me?", subtitle: String(localized: "You can change it later. Skip and she stays Mochi.")) {
            GroupedSection(inset: Space.l) {
                TextField(CatProfile.defaultName, text: $flow.catName)
                    .font(.nookiHeadline)
                    .submitLabel(.done)
                    .onChange(of: flow.catName) { _, new in
                        if new.count > CatProfile.nameLimit { flow.catName = String(new.prefix(CatProfile.nameLimit)) }
                    }
                    .rowCell()
            }
            GroupedSection(header: String(localized: "Ideas"), inset: Space.l) {
                ForEach(Self.nameIdeas, id: \.self) { idea in
                    optionRow(OnboardingOption(id: OnboardingOptionId(idea), label: LocalizedText(en: idea, ru: idea)),
                              multi: false, picked: flow.catName == idea) { flow.catName = idea }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: flow.catName) { _, new in Self.nameIdeas.contains(new) }
    }

    private var invite: some View {
        form(say: "I'm happier with two of you!",
             subtitle: String(localized: "Send them your code. They type it in Nooki to join you and \(CatProfile.name()).")) {
            if let pairing {
                switch pairing.state {
                case .waiting(let code, let expiresAt, _):
                    GroupedSection(inset: Space.l) {
                        Text(PairingCopy.spaced(code))
                            .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                            .foregroundStyle(Ink.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.s)
                            .accessibilityLabel("Your code: \(code)")
                            .rowCell()
                        ShareLink(item: inviteMessage(code)) {
                            Label("Share invite", systemImage: "square.and.arrow.up")
                                .font(.nookiHeadline)
                                .foregroundStyle(Ink.accentText)
                                .rowCell()
                                .frame(maxWidth: .infinity)
                        }
                        .simultaneousGesture(TapGesture().onEnded { flow.invited = true })
                    } footer: {
                        Text(PairingCopy.expiry(expiresAt: expiresAt, now: .now))
                    }
                case .choosing(nil, _) where !signedIn:
                    GroupedSection { progressRow("Connecting…") }
                case .creating, .claiming:
                    GroupedSection { progressRow("Getting your code…") }
                case .choosing(let failure, _):
                    VStack(alignment: .leading, spacing: Space.s) {
                        Button("Get my code") { pairing.createInvite() }
                            .buttonStyle(SecondaryButtonStyle())
                        if let failure {
                            Text(PairingCopy.message(for: failure))
                                .font(.nookiCaption)
                                .foregroundStyle(ShopInk.coral)
                                .padding(.horizontal, Space.l)
                        }
                    }
                case .paired:
                    GroupedSection {
                        Row(String(localized: "You're paired!"), symbol: "heart.fill", tint: UsTint.blush.color)
                    }
                }
            }
            if let demoPartner, !isPaired, !alreadyPaired {
                Section {
                    Button("Try with a demo partner", action: demoPartner)
                        .font(.nookiCallout)
                        .listRowSurface()
                }
            }
        }
    }

    private var join: some View {
        form(say: "Who's waiting for me?",
             subtitle: String(localized: "It's in the message your partner sent, or on their screen.")) {
            GroupedSection(inset: Space.l) {
                TextField("K7QM 4R2X HP", text: Binding { flow.joinCode } set: { flow.joinCode = Self.code(from: $0) })
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textContentType(.oneTimeCode)
                    .accessibilityLabel("Invite code")
                    .rowCell()
                PasteButton(payloadType: String.self) { strings in
                    guard let pasted = strings.first else { return }
                    Task { @MainActor in flow.joinCode = Self.code(from: pasted) }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .tint(.honey)
                .rowCell()
            } footer: {
                if case .choosing(let failure?, _) = pairing?.state {
                    Text(PairingCopy.message(for: failure))
                } else {
                    Text("10 letters and digits. There's no 0, O, 1 or I.")
                }
            }
        }
    }

    /// What was typed or pasted, kept to the symbols a code has.
    static func code(from typed: String) -> String {
        String(InviteCode.normalized(typed).filter { InviteCode.alphabet.contains($0) }.prefix(InviteCode.length))
    }

    private var stopped: some View {
        form(subtitle: String(localized: "Nooki is for 13 and up. Your cat will be waiting when you're older.")) {
            EmptyView()
        }
    }

    private var togetherSince: some View {
        form(say: "I'll count your days together!",
             subtitle: String(localized: "Only on this phone. You can change it in your profile.")) {
            GroupedSection {
                DatePicker("Together since", selection: $flow.togetherSince, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .rowCell()
            }
        }
    }

    private var notifications: some View {
        form(say: "I'll tell you when they think of you.",
             subtitle: String(localized: "Only for your partner and \(CatProfile.name()). Never ads.")) {
            GroupedSection {
                Row(String(localized: "Your partner drew you something"), symbol: "scribble.variable",
                              tint: UsTint.lilac.color)
                Row(String(localized: "\(CatProfile.name()) is hungry"), symbol: "fork.knife",
                              tint: UsTint.honey.color)
                Row(String(localized: "Your day together is tomorrow"), symbol: "heart.fill",
                              tint: UsTint.blush.color)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Examples of notifications")
        }
    }

    private var widget: some View {
        form(subtitle: String(localized: "Notes and \(CatProfile.name()), without opening the app.")) {
            GroupedSection {
                Row(String(localized: "Touch and hold the Home Screen"), symbol: "1.circle.fill",
                              tint: UsTint.honey.color)
                Row(String(localized: "Tap Edit, then Add Widget"), symbol: "2.circle.fill", tint: UsTint.honey.color)
                Row(String(localized: "Find Nooki and pick a size"), symbol: "3.circle.fill",
                              tint: UsTint.honey.color)
            }
        }
    }

    private func inviteMessage(_ code: String) -> String {
        guard let link = inviteBase?.appending(path: "i/\(code)") else {
            return String(localized: "Join me in Nooki! Open the app and enter my code: \(code)")
        }
        return String(localized: "Join me in Nooki! \(link.absoluteString) or enter my code: \(code)")
    }
}

/// A step's title: large, rounded, wrapping, and a header for VoiceOver.
struct PageTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.nookiLargeTitle)
            .foregroundStyle(Ink.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Mochi's round face, in her coat.
private struct Portrait: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image = UIImage(named: name) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "cat.fill").font(.system(size: size * 0.45)).foregroundStyle(Ink.heroInk)
            }
        }
        .frame(width: size, height: size)
        .background(RadialGradient(colors: [Color(hex: 0xFFF4E4), Color(hex: 0xF2C08A)], center: .init(x: 0.5, y: 0.35),
                                   startRadius: 0, endRadius: size * 0.75))
        .clipShape(.circle)
        .overlay(Circle().stroke(Ink.separator, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Mochi's face with what she says, the friendly anchor at the top of each step.
struct MochiSays: View {
    let text: LocalizedStringKey
    let avatar: String
    @Environment(\.dynamicTypeSize) private var typeSize

    init(text: LocalizedStringKey, avatar: String) {
        self.text = text
        self.avatar = avatar
    }

    var body: some View {
        // At accessibility sizes the bubble goes under her face, so its words keep the full width.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Space.m))
        layout {
            Portrait(name: avatar, size: 52)
            Text(text)
                .font(.nookiCallout.weight(.semibold))
                .foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .background(Ink.surface, in: .rect(cornerRadius: Radius.control))
        }
    }
}

private extension OnboardingStep {
    var isMulti: Bool { if case .multi = self { true } else { false } }

    var title: LocalizedText {
        switch self {
        case .single(let step), .multi(let step): step.title
        case .range(let step): step.title
        case .text(let step): step.title
        }
    }
}
