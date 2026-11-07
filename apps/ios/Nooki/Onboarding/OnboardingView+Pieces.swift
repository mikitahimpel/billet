import FeaturePairing
import SwiftUI
import Design
import Wire

extension OnboardingView {
    // MARK: Pieces

    /// Mochi with what she says, the subtitle, then the page's clay-card sections on the warm screen.
    func form<Content: View>(say: String? = nil, subtitle: String?,
                                     @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                VStack(alignment: .leading, spacing: Space.m) {
                    PageTitle(title)
                    if let say { MochiSays(text: LocalizedStringKey(say), avatar: flow.coat.avatar) }
                    if let subtitle {
                        Text(subtitle)
                            .font(.nookiCallout)
                            .foregroundStyle(Ink.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                content()
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.l)
            .padding(.bottom, Space.section)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }

    func optionRow(_ option: OnboardingOption, multi: Bool, picked: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                if let emoji = option.emoji { Text(emoji) }
                Text(option.label.text(for: language))
                    .font(.nookiBody)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 0)
                if multi {
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(picked ? Ink.accentText : Ink.textTertiary)
                        .font(.title3)
                } else if picked {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Ink.accentText)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .rowCell()
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    func progressRow(_ title: LocalizedStringKey) -> some View {
        HStack {
            Text(title)
                .font(.nookiBody)
                .foregroundStyle(Ink.text)
            Spacer()
            ProgressView().tint(Ink.accentText)
        }
        .rowCell()
    }

    @ViewBuilder var bottomBar: some View {
        if flow.page != .stopped {
            Button(action: primaryTapped) {
                Text(primaryTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canContinue)
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s)
            .padding(.bottom, Space.s)
            .background(Ink.screen.ignoresSafeArea(edges: .bottom))
        }
    }

    private func primaryTapped() {
        if flow.page == .join, let pairing {
            pairing.submit(code: flow.joinCode)
        } else {
            flow.continueTapped()
        }
    }

    private var primaryTitle: LocalizedStringKey {
        switch flow.page {
        case .welcome: "Let's go"
        case .join: isClaiming ? "Joining…" : "Join"
        case .invite: flow.invited ? "Continue" : "I'll invite them later"
        case .notifications: "Turn on notifications"
        case .widget: "Got it"
        default: "Continue"
        }
    }

    private var canContinue: Bool {
        switch flow.page {
        case .question: flow.answer != nil
        case .join: signedIn && !isClaiming && flow.joinCode.count == InviteCode.length
        default: true
        }
    }

    private var isClaiming: Bool {
        if case .claiming = pairing?.state { true } else { false }
    }

    func rangeBinding(_ range: OnboardingRangeStep) -> Binding<Int> {
        Binding { flow.values[range.id] ?? OnboardingFlow.initialValue(range) } set: { flow.values[range.id] = $0 }
    }

    func textBinding(_ field: OnboardingTextStep) -> Binding<String> {
        Binding { flow.texts[field.id] ?? "" } set: { flow.texts[field.id] = String($0.prefix(field.maxLength)) }
    }
}
