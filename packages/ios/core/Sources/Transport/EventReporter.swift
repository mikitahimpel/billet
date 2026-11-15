import Wire

/// Where features count what people do, from the closed list in `docs/analytics.md`. Recording
/// returns at once; sending happens later, off the caller's path.
public struct EventReporter: Sendable {
  private let record: @MainActor @Sendable (ClientEvent) -> Void

  public init(_ record: @escaping @MainActor @Sendable (ClientEvent) -> Void) {
    self.record = record
  }

  @MainActor
  public func callAsFunction(_ event: ClientEvent) {
    record(event)
  }

  @MainActor
  public func callAsFunction(_ name: ClientEventName, detail: String? = nil, value: Int? = nil) {
    record(ClientEvent(name, detail: detail, value: value))
  }

  /// For builds without an account to report to, previews and tests that don't count.
  public static let none = EventReporter { _ in }
}

/// The phone's waiting events (docs/analytics.md#on-the-phone): at most ``capacity``, the oldest
/// dropped past that; sent ``ReportEventsRequest/maxEvents`` to a request a few seconds after the
/// last one was recorded and whenever ``flush()`` is called. A batch the server refuses as invalid
/// is dropped; any other failure keeps it for the next flush.
@MainActor
public final class EventQueue {
  public static let capacity = 100

  public private(set) var pending: [ClientEvent]
  private let send: @Sendable ([ClientEvent]) async throws(TransportError) -> Void
  private let save: @MainActor ([ClientEvent]) -> Void
  private let delay: Duration
  private var sending = false
  private var scheduled: Task<Void, Never>?

  public init(
    saved: [ClientEvent], delay: Duration = .seconds(5),
    send: @escaping @Sendable ([ClientEvent]) async throws(TransportError) -> Void,
    save: @escaping @MainActor ([ClientEvent]) -> Void
  ) {
    pending = Array(saved.filter { $0.problem == nil }.suffix(Self.capacity))
    self.delay = delay
    self.send = send
    self.save = save
  }

  public var reporter: EventReporter {
    EventReporter { [weak self] event in self?.record(event) }
  }

  /// An event that breaks its name's rule is never kept, so no text or malformed id leaves the
  /// phone.
  public func record(_ event: ClientEvent) {
    guard event.problem == nil else { return }
    pending.append(event)
    if pending.count > Self.capacity { pending.removeFirst(pending.count - Self.capacity) }
    save(pending)
    guard scheduled == nil else { return }
    let delay = delay
    scheduled = Task { [weak self] in
      try? await Task.sleep(for: delay)
      self?.scheduled = nil
      await self?.flush()
    }
  }

  public func flush() async {
    guard !sending else { return }
    sending = true
    defer { sending = false }
    while !pending.isEmpty {
      let batch = Array(pending.prefix(ReportEventsRequest.maxEvents))
      do throws(TransportError) {
        try await send(batch)
      } catch {
        guard Self.isRefusal(error) else { return }
      }
      pending.removeFirst(min(batch.count, pending.count))
      save(pending)
    }
  }

  /// Sign-out, or analytics switched off.
  public func forget() {
    scheduled?.cancel()
    scheduled = nil
    pending = []
    save(pending)
  }

  private static func isRefusal(_ error: TransportError) -> Bool {
    switch error {
    case .api(.invalidRequest), .status(400): true
    case .network, .api, .status, .maintenance, .encoding, .decoding: false
    }
  }
}
