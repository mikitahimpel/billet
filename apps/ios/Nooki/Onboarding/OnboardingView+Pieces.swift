import FeaturePairing
import MomentsInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import Design
import UsInterface
import Wire

extension OnboardingView {
    // MARK: Pieces

    func form<Content: View>(say: String? = nil, subtitle: String?,
                                     @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                VStack(alignment: .leading, spacing: Space.m) {
                    PageTitle(title)
                    if let say { MochiSays(text: LocalizedStringKey(say), avatar: flow.coat.avatar) }
                    if let subtitle {
                        Text(subtitle)
                            .font(.ourioCallout)
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
        .ourioScrollEdges()
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
                    .font(.ourioBody)
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
                .font(.ourioBody)
                .foregroundStyle(Ink.text)
            Spacer()
            ProgressView().tint(Ink.accentText)
        }
        .rowCell()
    }

    /// Pinned under every page, the primary always last, `Space.s` above the safe area, so it sits in the same place
    /// on every page; a page's quiet secondary stacks above it and pushes nothing below.
    @ViewBuilder var actions: some View {
        if flow.page != .stopped {
            ActionSlot {
                primaryAction
                    .accessibilityIdentifier("onboarding.primary")
            } secondary: {
                secondaryAction
            }
            .modifier(WelcomeActionsReveal(start: flow.page == .welcome ? welcomeStart : nil))
        }
    }

    @ViewBuilder private var primaryAction: some View {
        if flow.page == .invite, case .waiting(let code, _, _)? = pairing?.state, !flow.invited {
            ShareLink(item: inviteMessage(code)) {
                Text("Share invite").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .simultaneousGesture(TapGesture().onEnded {
                flow.invited = true
                tapTick += 1
            })
        } else {
            Button(action: primaryTapped) {
                Text(primaryTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canContinue)
        }
    }

    @ViewBuilder private var secondaryAction: some View {
        switch flow.page {
        case .welcome where pairing != nil:
            Button("I have an invite code") {
                tapTick += 1
                flow.join()
            }
            .buttonStyle(QuietButtonStyle())
        case .invite:
            if case .waiting(let code, _, _)? = pairing?.state, flow.invited {
                ShareLink(item: inviteMessage(code)) { Text("Share again").frame(maxWidth: .infinity) }
                    .buttonStyle(QuietButtonStyle())
            } else if !flow.invited {
                Button("I'll invite them later") {
                    tapTick += 1
                    flow.continueTapped()
                }
                .buttonStyle(QuietButtonStyle())
            }
        case .welcome, .join, .question, .stopped, .togetherSince, .catCoat, .catName, .notifications, .widget:
            EmptyView()
        }
    }

    private func primaryTapped() {
        tapTick += 1
        if flow.page == .join, let pairing {
            pairing.submit(code: flow.joinCode)
        } else if flow.page == .invite, !flow.invited, let pairing {
            pairing.createInvite()
        } else {
            flow.continueTapped()
        }
    }

    private var primaryTitle: LocalizedStringKey {
        switch flow.page {
        case .welcome: "Let's go"
        case .join: isClaiming ? "Joining…" : "Join"
        case .invite: flow.invited ? "Continue" : failedInvite ? "Try again" : "Get my code"
        case .notifications: "Turn on notifications"
        case .widget: "Got it"
        default: "Continue"
        }
    }

    private var canContinue: Bool {
        switch flow.page {
        case .question: flow.answer != nil
        case .join:
            signedIn && !isClaiming && [InviteCode.length, InviteCode.reviewLength].contains(flow.joinCode.count)
        case .invite: flow.invited || isChoosing
        default: true
        }
    }

    private var isChoosing: Bool {
        if case .choosing? = pairing?.state { signedIn } else { false }
    }

    private var failedInvite: Bool { Self.failure(in: pairing?.state, on: .invite) != nil }

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

/// The welcome's actions come in on the script's last beat; every other page shows them at once.
private struct WelcomeActionsReveal: ViewModifier {
    let start: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let start, !reduceMotion {
            TimelineView(.animation) { context in
                let progress = WelcomeScript.standard.progress(.actions, at: context.date.timeIntervalSince(start))
                content.opacity(progress).offset(y: 10 * (1 - progress))
            }
        } else {
            content
        }
    }
}
