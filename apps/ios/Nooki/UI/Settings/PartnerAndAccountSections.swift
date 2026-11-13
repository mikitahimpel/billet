import AuthenticationServices
import Design
import FeatureOnboarding
import MomentsInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import Transport
import UsInterface
import Wire

/// Each action asks first; a failure says so and leaves everything as it was.
struct PartnerAndAccountSections: View {
    let session: ServerSession
    /// Wipes what is saved on this phone, closes Settings and starts the app over.
    var erase: () -> Void

    @Environment(\.startOver) private var startOver
    @Environment(\.authorizationController) private var authorizationController
    @State private var confirming: Action?
    @State private var reporting = false
    @State private var working: Busy?
    @State private var failed = false
    @State private var appleFailed = false
    @State private var reported = false

    private enum Busy {
        case unpair, report, block, deleteAccount
    }

    private enum Action: Identifiable {
        case unpair, block, deleteAccount
        var id: Self { self }
    }

    var body: some View {
        Group {
            if session.isPaired {
                GroupedSection(header: "Partner", footer: reported
                    ? "Thank you. We read every report."
                    : "Unpairing ends the pair for both of you. Blocking also keeps the two of you from pairing again.") {
                    button("Unpair", busy: .unpair, symbol: "person.2.slash.fill", tint: .honey) { confirming = .unpair }
                    button("Report partner", busy: .report, symbol: "flag.fill", tint: .sun) { reporting = true }
                    button("Block partner", busy: .block, symbol: "hand.raised.fill", tint: .coral, destructive: true) {
                        confirming = .block
                    }
                }
            }
            GroupedSection(header: "Delete account",
                           footer: "Removes your account and what you sent from the server, and takes this phone back to the start.") {
                button("Delete account", busy: .deleteAccount, symbol: "person.crop.circle.badge.minus", tint: .coral, destructive: true) {
                    confirming = .deleteAccount
                }
            }
        }
        .disabled(working != nil)
        .confirmationDialog(title, isPresented: isConfirming, titleVisibility: .visible, presenting: confirming) { action in
            Button(label(action), role: .destructive) { run(action) }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(message(action))
        }
        .confirmationDialog("Report your partner", isPresented: $reporting, titleVisibility: .visible) {
            ForEach(ReportReason.allCases, id: \.self) { reason in
                Button(reason.title) { report(reason) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("What happened?")
        }
        .alert(appleFailed ? "Apple didn't confirm" : "That didn't work", isPresented: showingFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appleFailed
                 ? "Nothing was deleted. Try again in a moment."
                 : "The server didn't answer. Nothing changed; try again in a moment.")
        }
    }

    private func button(
        _ title: String, busy: Busy, symbol: String, tint: UsTint, destructive: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Row(title, symbol: symbol, tint: tint.color, destructive: destructive) {
                if working == busy { ProgressView() }
            }
        }
        .buttonStyle(PressScaleStyle())
    }

    private var showingFailure: Binding<Bool> {
        Binding(get: { failed || appleFailed }, set: { if !$0 { failed = false; appleFailed = false } })
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }

    private var title: String {
        switch confirming {
        case .unpair: "Unpair from your partner?"
        case .block: "Block your partner?"
        case .deleteAccount: "Delete your account?"
        case nil: ""
        }
    }

    private func label(_ action: Action) -> String {
        switch action {
        case .unpair: "Unpair"
        case .block: "Block"
        case .deleteAccount: "Delete account"
        }
    }

    private func message(_ action: Action) -> String {
        switch action {
        case .unpair: "You stop sharing with each other. You can pair again with a new code."
        case .block: "You are unpaired, and neither of you can pair with the other again."
        case .deleteAccount:
            "Your account and what you sent are deleted from the server, your partner is unpaired, and "
                + "everything on this phone is erased. If you signed in with Apple, Apple asks you once more, "
                + "and Ourio's access to your Apple ID ends. This can't be undone."
        }
    }

    private static func busy(for action: Action) -> Busy {
        switch action {
        case .unpair: .unpair
        case .block: .block
        case .deleteAccount: .deleteAccount
        }
    }

    private func run(_ action: Action) {
        Task {
            working = Self.busy(for: action)
            defer { working = nil }
            do {
                switch action {
                case .unpair: try await session.unpair()
                case .block: try await session.blockPartner()
                case .deleteAccount:
                    var code: String?
                    if try await session.isAppleLinked() {
                        code = try await AppleAuthorizationCode.fresh(using: authorizationController)
                    }
                    try await session.deleteAccount(appleAuthorizationCode: code)
                    erase()
                    startOver()
                }
            } catch let failure as AppleAuthorizationCode.Failure {
                appleFailed = failure == .failed
            } catch {
                failed = true
            }
        }
    }

    private func report(_ reason: ReportReason) {
        Task {
            working = .report
            defer { working = nil }
            do {
                try await session.reportPartner(reason, details: nil)
                reported = true
            } catch {
                failed = true
            }
        }
    }
}

extension ReportReason {
    var title: String {
        switch self {
        case .harassment: "Harassment"
        case .inappropriate: "Inappropriate content"
        case .unsafe: "I don't feel safe"
        case .spam: "Spam"
        case .other: "Something else"
        }
    }
}
