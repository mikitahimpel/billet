import FeaturePairing
import SwiftUI
import Wire

/// The first launch, drawn over the live room: a welcome, then one step per screen with a progress bar, Back, Skip
/// and a Continue button. Server questions are drawn by their kind, so a new question needs no app update.
struct OnboardingView: View {
    @Bindable var flow: OnboardingFlow
    /// The invite comes from the pairing on the server; nil in a build without one.
    let pairing: PairingModel?
    /// The invite needs the account; until the sign-in finishes the page waits for it.
    var signedIn = false

    private let language = Locale.current.language.languageCode?.identifier

    var body: some View {
        ZStack {
            if flow.page == .welcome {
                LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                welcome
            } else {
                Ink.sheet.opacity(0.93).ignoresSafeArea()
                step
            }
        }
        .animation(.spring(duration: 0.35), value: flow.index)
        .task { await flow.load() }
        .onChange(of: flow.index, initial: true) { flow.appeared() }
        .task(id: [flow.page == .invite, signedIn]) {
            guard flow.page == .invite, signedIn, let pairing, case .choosing(nil, _) = pairing.state else { return }
            pairing.createInvite()
        }
        .preferredColorScheme(.dark)
        .tint(Color(hex: 0xFFC27A))
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("Meet Mochi")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.primary)
            Text("A cat the two of you look after together. A few quick questions first, so Nooki fits you.")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            primaryButton("Let's go") { flow.start() }
                .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    // MARK: Steps

    private var step: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            bottomBar
        }
        .id(flow.index)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { flow.back() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Ink.primary)
                    .frame(width: 40, height: 40)
                    .background(Ink.card, in: .circle)
            }
            .accessibilityLabel("Back")
            ProgressCapsule(value: flow.progress)
                .animation(.spring(duration: 0.4), value: flow.progress)
            Button("Skip") { flow.skip() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Ink.secondary)
                .opacity(flow.canSkip ? 1 : 0)
                .disabled(!flow.canSkip)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder private var content: some View {
        switch flow.page {
        case .welcome:
            EmptyView()
        case .question(let step):
            question(step)
        case .catCoat:
            catCoat
        case .catName:
            catName
        case .invite:
            invite
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            switch flow.page {
            case .invite:
                primaryButton(flow.invited ? "Continue" : "I'll invite them later") { flow.continueTapped() }
            case .catName, .catCoat:
                primaryButton("Continue") { flow.continueTapped() }
            default:
                primaryButton("Continue") { flow.continueTapped() }
                    .disabled(flow.answer == nil)
                    .opacity(flow.answer == nil ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    // MARK: Server questions

    @ViewBuilder private func question(_ step: OnboardingStep) -> some View {
        switch step {
        case .single(let choice), .multi(let choice):
            heading(choice.title, choice.subtitle)
            VStack(spacing: 10) {
                ForEach(choice.options, id: \.id) { option in
                    optionCard(option, multi: step.isMulti, picked: flow.picks[choice.id]?.contains(option.id) ?? false) {
                        flow.toggle(option, in: step)
                    }
                }
            }
        case .range(let range):
            heading(range.title, range.subtitle)
            Picker("", selection: rangeBinding(range)) {
                ForEach(Array(stride(from: range.min, through: range.max, by: range.step)), id: \.self) { value in
                    Text(range.unit.map { "\(value) \($0.text(for: language))" } ?? "\(value)").tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
        case .text(let field):
            heading(field.title, field.subtitle)
            textField(field.placeholder?.text(for: language) ?? "", text: textBinding(field), limit: field.maxLength)
        }
    }

    private func rangeBinding(_ range: OnboardingRangeStep) -> Binding<Int> {
        Binding { flow.values[range.id] ?? OnboardingFlow.initialValue(range) } set: { flow.values[range.id] = $0 }
    }

    private func textBinding(_ field: OnboardingTextStep) -> Binding<String> {
        Binding { flow.texts[field.id] ?? "" } set: { flow.texts[field.id] = String($0.prefix(field.maxLength)) }
    }

    // MARK: Coat

    @ViewBuilder private var catCoat: some View {
        bubble("Which one am I?")
        heading("Choose your cat", "Swipe to see every coat.")
        ScrollViewReader { proxy in coatCarousel.onAppear { proxy.scrollTo(flow.coat, anchor: .center) } }
        HStack(spacing: 8) {
            ForEach(CatCoat.allCases, id: \.self) { coat in
                Capsule()
                    .fill(coat == flow.coat ? Color.honey : Ink.hairline)
                    .frame(width: coat == flow.coat ? 20 : 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(duration: 0.3), value: flow.coat)
    }

    /// One card per coat; the one in the middle is the pick, and it opens on the coat picked before.
    private var coatCarousel: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(CatCoat.allCases, id: \.self) { coat in
                    coatCard(coat)
                        .containerRelativeFrame(.horizontal, count: 4, span: 3, spacing: 14)
                        .scrollTransition(axis: .horizontal) { card, phase in
                            card.scaleEffect(phase.isIdentity ? 1 : 0.88).opacity(phase.isIdentity ? 1 : 0.6)
                        }
                        .id(coat)
                        .onTapGesture { withAnimation(.spring(duration: 0.35)) { flow.coat = coat } }
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: Binding { Optional(flow.coat) } set: { if let coat = $0 { flow.coat = coat } },
                        anchor: .center)
        .contentMargins(.horizontal, 32, for: .scrollContent)
        .padding(.horizontal, -24)
    }

    private func coatCard(_ coat: CatCoat) -> some View {
        let picked = coat == flow.coat
        return VStack(spacing: 10) {
            Image(uiImage: UIImage(named: coat.portrait) ?? UIImage())
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 280)
                .padding(.top, 18)
            Text(coat.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.heroInk)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(RadialGradient(colors: [Color(hex: 0xFFF4E4), Color(hex: 0xF2C08A)], center: .init(x: 0.5, y: 0.35),
                                   startRadius: 10, endRadius: 260),
                    in: .rect(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(picked ? Color.honey : .clear, lineWidth: 3))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Cat name

    private static let nameIdeas = ["Mochi", "Tofu", "Biscuit", "Pumpkin", "Luna", "Miso"]

    @ViewBuilder private var catName: some View {
        bubble("What should we call me?")
        heading("Name your cat", "You can change it later. Skip and she stays Mochi.")
        textField(CatProfile.defaultName, text: $flow.catName, limit: CatProfile.nameLimit)
        FlowRow(spacing: 8) {
            ForEach(Self.nameIdeas, id: \.self) { idea in
                Button { flow.catName = idea } label: {
                    Text(idea)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(flow.catName == idea ? Ink.heroInk : Ink.primary)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(flow.catName == idea ? AnyShapeStyle(.honeyGradient) : AnyShapeStyle(Ink.card),
                                    in: .capsule)
                }
                .buttonStyle(PressScaleStyle())
            }
        }
    }

    // MARK: Invite

    @ViewBuilder private var invite: some View {
        bubble("I'm happier with two of you!")
        heading("Invite your partner", "Send them your code. They type it in Nooki to join you and \(CatProfile.name()).")
        if let pairing {
            switch pairing.state {
            case .waiting(let code, let expiresAt, _):
                VStack(spacing: 12) {
                    Text(PairingCopy.spaced(code))
                        .font(.system(size: 38, weight: .bold, design: .monospaced))
                        .foregroundStyle(Ink.primary)
                    Text(PairingCopy.expiry(expiresAt: expiresAt, now: .now))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.secondary)
                    ShareLink(item: "Join me in Nooki! Open the app and enter my code: \(code)") {
                        Label("Share invite", systemImage: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Ink.primary)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Ink.card, in: .capsule)
                    }
                    .simultaneousGesture(TapGesture().onEnded { flow.invited = true })
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(Ink.card, in: .rect(cornerRadius: 24))
            case .creating, .claiming:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, minHeight: 160)
            case .choosing(nil, _) where !signedIn:
                ProgressView("Connecting…").controlSize(.large).frame(maxWidth: .infinity, minHeight: 160)
            case .choosing(let failure, _):
                if let failure {
                    Text(PairingCopy.message(for: failure))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: 0xFF8A7A))
                }
                Button("Get my code") { pairing.createInvite() }
                    .font(.system(size: 17, weight: .semibold))
            case .paired:
                Text("You're paired!")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.primary)
            }
        }
    }

    // MARK: Pieces

    private func heading(_ title: LocalizedText, _ subtitle: LocalizedText?) -> some View {
        heading(title.text(for: language), subtitle?.text(for: language))
    }

    private func heading(_ title: String, _ subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Ink.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Mochi saying something, as a little speech bubble beside her face.
    private func bubble(_ text: String) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(systemName: "cat.fill")
                .font(.system(size: 22))
                .foregroundStyle(Ink.heroInk)
                .frame(width: 46, height: 46)
                .background(.honeyGradient, in: .circle)
            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.heroInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: 0xFFF4E4), in: .rect(cornerRadius: 18))
        }
    }

    private func optionCard(_ option: OnboardingOption, multi: Bool, picked: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let emoji = option.emoji { Text(emoji).font(.system(size: 22)) }
                Text(option.label.text(for: language))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Ink.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: picked
                      ? (multi ? "checkmark.square.fill" : "largecircle.fill.circle")
                      : (multi ? "square" : "circle"))
                    .font(.system(size: 20))
                    .foregroundStyle(picked ? Color.honey : Ink.hairline)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
            .background(Ink.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(picked ? Color.honey : .clear, lineWidth: 2))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private func textField(_ placeholder: String, text: Binding<String>, limit: Int) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(Ink.primary)
            .submitLabel(.done)
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(Ink.card, in: .rect(cornerRadius: 18))
            .onChange(of: text.wrappedValue) { _, new in
                if new.count > limit { text.wrappedValue = String(new.prefix(limit)) }
            }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.heroInk)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Capsule().fill(.honeyGradient))
                .shadow(color: Color.honeyDeep.opacity(0.4), radius: 10, y: 4)
        }
        .buttonStyle(PressScaleStyle())
    }
}

private extension OnboardingStep {
    var isMulti: Bool { if case .multi = self { true } else { false } }
}

/// Lays its children out in rows, wrapping to the next row when one is full.
private struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
