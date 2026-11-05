import FeaturePairing
import SwiftUI

/// Pairs this phone with the partner's: one shows a code, the other types it in. Whoever shows the code waits here
/// while the sheet checks every few seconds whether it was claimed.
struct PairingSheet: View {
    let model: PairingModel
    /// The code from an invite link.
    var prefill = ""
    /// Called once when the pairing is done and the user taps Done.
    var finished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    content
                }
                .padding(.horizontal, Space.gutter)
                .padding(.vertical, Space.m)
            }
            .scrollIndicators(.hidden)
            .background(Ink.screen.ignoresSafeArea())
            .navigationTitle("Pair with your partner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isPaired {
                        Button("Cancel") {
                            model.cancel()
                            dismiss()
                        }
                    }
                }
            }
        }
        .tint(.honey)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isPaired)
        .onAppear { if code.isEmpty { code = prefill } }
        .task(id: waitingCode) {
            guard waitingCode != nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: PairingModel.checkEvery)
                model.tick()
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .choosing(let failure, _):
            if let failure {
                Text(PairingCopy.message(for: failure))
                    .font(.nookiCallout)
                    .foregroundStyle(ShopInk.coral)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            showCard
            enterCard
        case .creating, .claiming:
            ProgressView()
                .controlSize(.large)
                .tint(Ink.accentText)
                .frame(maxWidth: .infinity, minHeight: 260)
        case .waiting(let code, let expiresAt, _):
            waitingCard(code: code, expiresAt: expiresAt)
        case .paired:
            pairedCard
        }
    }

    private var showCard: some View {
        card {
            UsIcon(glyph: .init(symbol: "qrcode", tint: .honey), size: 52)
            Text("Show my code")
                .font(.nookiTitle)
                .foregroundStyle(Ink.text)
            Text("Your partner types it into Nooki on their phone.")
                .font(.nookiCallout)
                .foregroundStyle(Ink.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                typing = false
                model.createInvite()
            } label: {
                Text("Get a code").frame(maxWidth: .infinity)
            }
            .nookiPrimary()
        }
    }

    private var enterCard: some View {
        card {
            UsIcon(glyph: .init(symbol: "keyboard", tint: .blush), size: 52)
            Text("I have their code")
                .font(.nookiTitle)
                .foregroundStyle(Ink.text)
            TextField("Code", text: $code)
                .font(.system(.title2, design: .monospaced, weight: .semibold))
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($typing)
                .submitLabel(.join)
                .onSubmit(submit)
                .padding(.vertical, Space.m)
                .background(Ink.surfaceRaised, in: .rect(cornerRadius: Radius.control))
            Button("Pair", action: submit)
                .buttonStyle(NookiSecondaryStyle())
            .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func waitingCard(code: String, expiresAt: Int) -> some View {
        card {
            Text("Your code")
                .font(.nookiHeadline)
                .foregroundStyle(Ink.textSecondary)
            Text(PairingCopy.spaced(code))
                .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                .foregroundStyle(Ink.text)
                .textSelection(.enabled)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(PairingCopy.expiry(expiresAt: expiresAt, now: context.date))
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.textSecondary)
                    .monospacedDigit()
            }
            HStack(spacing: Space.s) {
                ProgressView().tint(Ink.accentText)
                Text("Waiting for your partner…")
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.text)
            }
            .padding(.top, 4)
            ShareLink(item: "Pair with me on Nooki: \(code)") {
                Label("Send the code", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(NookiSecondaryStyle())
        }
    }

    private var pairedCard: some View {
        card {
            UsIcon(glyph: .init(symbol: "heart.fill", tint: .blush), size: 64)
                .symbolEffect(.bounce, options: .nonRepeating)
            Text("You're paired!")
                .font(.nookiTitle)
                .foregroundStyle(Ink.text)
            Text("Notes you pin now reach your partner's Nooki.")
                .font(.nookiCallout)
                .foregroundStyle(Ink.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                finished()
                dismiss()
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .nookiPrimary()
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: Space.m, content: content)
            .padding(Space.gutter)
            .frame(maxWidth: .infinity)
            .nookiCard()
    }

    private var isPaired: Bool {
        if case .paired = model.state { true } else { false }
    }

    private var waitingCode: String? {
        if case .waiting(let code, _, _) = model.state { code } else { nil }
    }

    private func submit() {
        typing = false
        model.submit(code: code)
    }
}

/// The words the pairing sheet uses, kept apart so they can be tested.
enum PairingCopy {
    static func message(for failure: PairingFailure) -> String {
        switch failure {
        case .invalidCode: "That code isn't working. It may be mistyped, expired, already used or your own."
        case .alreadyPaired: "You already have a partner."
        case .signedOut: "This phone was signed out. Open Nooki again to sign back in."
        case .unavailable: "Nooki can't reach its server right now. Try again in a moment."
        }
    }

    /// The code in groups of four, easier to read aloud: "ABCD EFGH".
    static func spaced(_ code: String) -> String {
        var out = ""
        for (index, character) in code.enumerated() {
            if index > 0, index.isMultiple(of: 4) { out.append(" ") }
            out.append(character)
        }
        return out
    }

    /// "Expires in 9:41", or that it has expired. `expiresAt` is epoch milliseconds.
    static func expiry(expiresAt: Int, now: Date) -> String {
        let seconds = Int((Double(expiresAt) / 1000 - now.timeIntervalSince1970).rounded(.down))
        guard seconds > 0 else { return "This code has expired" }
        return "Expires in \(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}
