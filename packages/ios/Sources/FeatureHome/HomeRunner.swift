import Pet

/// Runs ``HomeMachine`` outputs.
enum HomeRunner {
  static func run(
    _ output: HomeMachine.Output,
    delivery: NoteDelivery,
    sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
  ) async -> HomeMachine.Event? {
    switch output {
    case .deliver(let strokes, let id):
      await delivery.deliver(strokes, id)
      return nil
    case .pet(let output):
      return .pet(await PetRunner.run(output, sleep: sleep))
    }
  }
}
