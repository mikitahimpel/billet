/// Runs ``PetMachine`` outputs: each deadline waits, then finishes its step.
public enum PetRunner {
  /// Longest a scene may take over a delivery, or over settling. A scene's own pacing stays below
  /// these, so they only fire when it hangs.
  public static let deliveryDeadline = Duration.seconds(20)
  public static let settlingDeadline = Duration.seconds(6)

  public static func run(
    _ output: PetMachine.Output,
    sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
  ) async -> PetMachine.Event {
    switch output {
    case .deliveryDeadline(let delivery):
      await sleep(deliveryDeadline)
      return .deliveryFinished(delivery: delivery)
    case .settlingDeadline(let delivery):
      await sleep(settlingDeadline)
      return .settled(delivery: delivery)
    }
  }
}
