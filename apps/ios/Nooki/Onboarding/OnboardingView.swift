import FeaturePairing
import OurioShared
import SwiftUI
import Design
import Wire

/// Server questions are drawn by their kind, so a new question needs no app update.
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

    @State private var scanning = false
    @State private var errorTick = 0
    @State var tapTick = 0
    @State private var wavedTick = 0
    @State var welcomeStart = Date()
    /// Only with `-uitestWelcomeProbe`: counts the welcome timeline's late frames. The UI test adds
    /// `-uitestWelcomeProbeHarness` and signals when its launch handling is done.
    @State private var probe: HitchProbe? = ProcessInfo.processInfo.arguments.contains("-uitestWelcomeProbe")
        ? HitchProbe(waitsForHarness: ProcessInfo.processInfo.arguments.contains("-uitestWelcomeProbeHarness")) : nil

    /// One persistent background and header; only the page between the header and the actions changes.
    var body: some View {
        ZStack {
            Ink.screen.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                page
                    .id(flow.index)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
                        .combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                actions
            }
        }
        .tint(Ink.accentText)
        .animation(.smooth(duration: 0.35), value: flow.index)
        .sensoryFeedback(.selection, trigger: flow.picks)
        .haptic(.selection, trigger: flow.coat)
        .haptic(.step, trigger: flow.index)
        .haptic(.tap, trigger: tapTick)
        .haptic(.tap, trigger: wavedTick)
        .haptic(.confirmed, trigger: isPaired)
        .haptic(.rejected, trigger: errorTick)
        .overlay(alignment: .topLeading) { probeLabel }
        .task { await flow.load() }
        .onChange(of: flow.index, initial: true) { flow.appeared() }
        // A failure belongs to the step it happened on: leaving the step clears it.
        .onChange(of: flow.index) { clearFailure() }
        .onChange(of: pairing?.state) { _, state in
            if Self.failure(in: state, on: flow.page) != nil { errorTick += 1 }
        }
        .task(id: [flow.page == .invite, signedIn]) {
            guard flow.page == .invite, signedIn, let pairing, case .choosing(nil, _) = pairing.state else { return }
            pairing.createInvite()
        }
        .onChange(of: isPaired || alreadyPaired, initial: true) { _, joined in
            guard joined else { return }
            flow.partnerJoined()
            if isPaired { paired() }
        }
        .sheet(isPresented: $scanning) { scanner }
    }

    @ViewBuilder private var probeLabel: some View {
        if let summary = probe?.summary {
            Text(summary)
                .font(.ourioMicro)
                .foregroundStyle(.clear)
                .accessibilityIdentifier("welcome.probe")
                .accessibilityLabel(summary)
        }
    }

    /// The failure a page may show: a wrong code belongs to the code step, never to the invite.
    static func failure(in state: PairingMachine.State?, on page: OnboardingFlow.Page) -> PairingFailure? {
        guard case .choosing(let failure?, _)? = state else { return nil }
        switch page {
        case .join: return failure
        case .invite: return failure == .invalidCode ? nil : failure
        case .welcome, .question, .stopped, .togetherSince, .catCoat, .catName, .notifications, .widget: return nil
        }
    }

    func clearFailure() {
        if case .choosing(.some, _)? = pairing?.state { pairing?.cancel() }
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

    /// Back, progress and Skip, in a row of a fixed height so the pages never move under it. The welcome and the
    /// stop screen keep the row, empty.
    private var header: some View {
        HStack {
            if showsHeader {
                Button { flow.back() } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: Size.control, height: Size.control)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Back")
                ProgressView(value: flow.progress)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Step \(flow.index) of \(flow.pages.count - 1)")
                if flow.canSkip {
                    Button("Skip") { flow.skip() }
                        .font(.ourioBody)
                        .frame(minWidth: Size.control, minHeight: Size.control)
                } else {
                    Color.clear.frame(width: Size.control, height: Size.control)
                }
            }
        }
        .padding(.horizontal, Space.s)
        .frame(height: Size.control + Space.s)
    }

    private var showsHeader: Bool { flow.page != .welcome && flow.page != .stopped }

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

    private var welcome: some View {
        WelcomeView(start: welcomeStart, waved: { wavedTick += 1 }, probe: probe)
            .onAppear { probe?.restart = { welcomeStart = .now } }
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
                Field(field.placeholder?.text(for: language) ?? "", text: textBinding(field))
                    .submitLabel(.done)
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
            Field(CatProfile.defaultName, text: $flow.catName, font: .ourioHeadline)
                .submitLabel(.done)
                .onChange(of: flow.catName) { _, new in
                    if new.count > CatProfile.nameLimit { flow.catName = String(new.prefix(CatProfile.nameLimit)) }
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
             subtitle: String(localized: "Send them your code. They type it in Ourio to join you and \(CatProfile.name()).")) {
            if let pairing {
                switch pairing.state {
                case .waiting(let code, let expiresAt, _):
                    GroupedSection(inset: Space.l) {
                        Text(PairingCopy.spaced(code))
                            .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                            .foregroundStyle(Ink.text)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.s)
                            .accessibilityLabel("Your code: \(code)")
                            .rowCell()
                        if let image = QRCode.image(for: inviteLink(code)) {
                            Image(uiImage: image)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 160, height: 160)
                                .padding(Space.s)
                                .background(.white, in: .rect(cornerRadius: Radius.inner))
                                .frame(maxWidth: .infinity)
                                .rowCell()
                                .accessibilityLabel("QR code of your invite")
                        }
                    } footer: {
                        Text(PairingCopy.expiry(expiresAt: expiresAt, now: .now))
                    }
                case .choosing(nil, _) where !signedIn:
                    GroupedSection { progressRow("Connecting…") }
                case .creating, .claiming:
                    GroupedSection { progressRow("Getting your code…") }
                case .choosing:
                    if let failure = Self.failure(in: pairing.state, on: .invite) {
                        ErrorLine(PairingCopy.message(for: failure))
                    }
                case .paired:
                    GroupedSection {
                        Row(String(localized: "You're paired!"), symbol: "heart.fill", tint: UsTint.blush.color)
                    }
                }
            }
            if let demoPartner, !isPaired, !alreadyPaired {
                Button("Try with a demo partner", action: demoPartner)
                    .buttonStyle(SecondaryButtonStyle(fullWidth: false))
                    .font(.ourioCallout)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var join: some View {
        let failure = Self.failure(in: pairing?.state, on: .join)
        return form(say: "Who's waiting for me?",
             subtitle: String(localized: "It's in the message your partner sent, or on their screen.")) {
            VStack(spacing: Space.s) {
                Field("K7QM 4R2X HP", text: Binding { flow.joinCode } set: { typed in
                    flow.joinCode = Self.code(from: typed)
                    clearFailure()
                }, font: .system(.title2, design: .monospaced, weight: .bold), failed: failure != nil)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textContentType(.oneTimeCode)
                    .accessibilityLabel("Invite code")
                if failure != nil {
                    ErrorLine(String(localized: "This code didn't work. Check it or ask for a new one."))
                }
                HStack(spacing: Space.s) {
                    Button { pasteCode() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                        .buttonStyle(SecondaryButtonStyle())
                    if InviteScanner.isAvailable {
                        Button { scanning = true } label: { Label("Scan", systemImage: "qrcode.viewfinder") }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                Text("10 letters and digits. There's no 0, O, 1 or I.")
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { if flow.joinCode.isEmpty { pasteCode(onlyIfCode: true) } }
    }

    private var scanner: some View {
        InviteScanner { code in
            scanning = false
            flow.joinCode = code
            tapTick += 1
        }
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            GlassIconButton(symbol: "xmark", label: "Close") { scanning = false }
                .padding(Space.gutter)
        }
    }

    /// Fills the field from the clipboard. Reading it is what asks iOS for the paste permission.
    private func pasteCode(onlyIfCode: Bool = false) {
        guard UIPasteboard.general.hasStrings, let text = UIPasteboard.general.string else { return }
        if let code = InviteInput.code(in: text) {
            flow.joinCode = code
            clearFailure()
        } else if !onlyIfCode {
            flow.joinCode = Self.code(from: text)
        }
    }

    private func inviteLink(_ code: String) -> String {
        inviteBase?.appending(path: "i/\(code)").absoluteString ?? code
    }

    /// What was typed or pasted, kept to the symbols a code has, up to the App Review pair's longer code.
    static func code(from typed: String) -> String {
        String(InviteCode.normalized(typed).filter { InviteCode.alphabet.contains($0) }.prefix(InviteCode.reviewLength))
    }

    private var stopped: some View {
        form(subtitle: String(localized: "Ourio is for 13 and up. Your cat will be waiting when you're older.")) {
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
                Row(String(localized: "Find Ourio and pick a size"), symbol: "3.circle.fill",
                              tint: UsTint.honey.color)
            }
        }
    }

    func inviteMessage(_ code: String) -> String {
        guard let link = inviteBase?.appending(path: "i/\(code)") else {
            return String(localized: "Join me in Ourio! Open the app and enter my code: \(code)")
        }
        return String(localized: "Join me in Ourio! \(link.absoluteString) or enter my code: \(code)")
    }
}

struct PageTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.ourioLargeTitle)
            .foregroundStyle(Ink.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

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
                .font(.ourioCallout.weight(.semibold))
                .foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .background(Ink.surface, in: .rect(cornerRadius: Radius.card))
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
