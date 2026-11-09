import SwiftUI

public struct MockPaymentsLabsView: View {
  private let payments: MockPayments
  private let switches: MockSwitches
  @State private var outcome: MockSwitches.Outcome
  @State private var pending = 0
  @State private var message: String?

  public init(payments: MockPayments, switches: MockSwitches) {
    self.payments = payments
    self.switches = switches
    _outcome = State(initialValue: switches.outcome)
  }

  public var body: some View {
    Section {
      Picker("Next purchase", selection: $outcome) {
        ForEach(MockSwitches.Outcome.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      .onChange(of: outcome) { _, new in switches.outcome = new }
      Button("Approve Ask to Buy (\(pending))") { run { try await payments.approvePending() } }
        .disabled(pending == 0)
      Button("Decline Ask to Buy") {
        payments.declinePending()
        pending = payments.pendingCount
      }
      .disabled(pending == 0)
      Button("Refund last purchase") {
        run {
          let refunded = try await payments.refundLast()
          message = refunded ? "Refunded." : "Nothing bought since launch."
        }
      }
      if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
    } header: {
      Text("Payments (mock store)")
    } footer: {
      Text("This build fakes the App Store. Stamps are credited by the dev server's mock route.")
    }
    .task {
      while !Task.isCancelled {
        pending = payments.pendingCount
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }

  private func run(_ action: @escaping @MainActor () async throws -> Void) {
    Task { @MainActor in
      do {
        try await action()
        pending = payments.pendingCount
      } catch {
        message = "Failed: \(error)"
      }
    }
  }
}
