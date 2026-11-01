import Wire

/// Hands a finished drawing to whoever receives notes, and returns when it has arrived.
///
/// Real delivery replaces ``NoteDelivery/localFake``: encode the strokes, send them through the
/// outbox, and let `HomeMachine.Event.noteArrived` come from an incoming note instead.
public struct NoteDelivery: Sendable {
  public var deliver: @Sendable ([Stroke]) async -> Void

  public init(deliver: @escaping @Sendable ([Stroke]) async -> Void) {
    self.deliver = deliver
  }

  /// FAKE. Nothing leaves the device and the drawing is dropped: the sender's own cat plays the
  /// delivery straight away, with no backend, pairing or partner involved.
  public static let localFake = NoteDelivery { _ in }
}
