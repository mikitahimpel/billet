/// Runs ``HomeMachine`` outputs. The holds mirror the animation lengths in `LittleHouse.riv`.
enum HomeRunner {
  /// Deliver runs 590 frames at 60 fps, then the cat sits proudly for one 4 s Proud loop.
  static let deliveryHold = Duration.seconds(590.0 / 60.0 + 4)
  /// Settle runs 150 frames at 60 fps.
  static let settlingHold = Duration.seconds(150.0 / 60.0)

  static func run(
    _ output: HomeMachine.Output,
    delivery: NoteDelivery,
    sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
  ) async -> HomeMachine.Event? {
    switch output {
    case .deliver(let strokes):
      await delivery.deliver(strokes)
      return nil
    case .holdDelivery:
      await sleep(deliveryHold)
      return .deliveryPlayed
    case .holdSettling:
      await sleep(settlingHold)
      return .settlingPlayed
    }
  }
}
