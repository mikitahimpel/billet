import Foundation
import Observation
import Transport
import Wire

/// The cat events this phone still owes the pair's journal, kept in a file until the server has each one. They pay
/// the earned coins, so a pet on the subway goes up once the phone is back online, under the key it was made with.
@MainActor
@Observable
final class CatEventOutbox {
    /// Most events kept; past it the oldest go, so a phone that never reaches the server doesn't grow the file.
    static let limit = 200

    private(set) var pending: [RecordCatEventRequest]
    @ObservationIgnored private let client: CatEventsClient
    @ObservationIgnored private let file: URL
    @ObservationIgnored private var flushing = false

    init(client: CatEventsClient, file: URL = CatEventOutbox.defaultFile) {
        self.client = client
        self.file = file
        let saved = try? Data(contentsOf: file)
        pending = saved.flatMap { try? JSONDecoder().decode([RecordCatEventRequest].self, from: $0) } ?? []
    }

    nonisolated static var defaultFile: URL {
        URL.applicationSupportDirectory.appending(path: "Outbox/cat-events.json")
    }

    /// Keeps `events`, each under a fresh key, and tries to send everything waiting.
    func send(_ events: [CatEvent]) async {
        guard !events.isEmpty else { return }
        pending.append(contentsOf: events.map { RecordCatEventRequest(id: .make(), event: $0) })
        if pending.count > Self.limit { pending.removeFirst(pending.count - Self.limit) }
        save()
        _ = await flush()
    }

    /// Sends what is waiting, oldest first, and forgets each one the server took or refused. True when one is still
    /// waiting because the server couldn't be reached; the rest stay for the next try in the same order.
    func flush() async -> Bool {
        guard !flushing else { return !pending.isEmpty }
        flushing = true
        defer { flushing = false }
        while let request = pending.first {
            guard !Task.isCancelled else { return true }
            do {
                _ = try await client.record(request)
            } catch {
                if error.isWorthRetrying { return true }
            }
            pending.removeAll { $0.id == request.id }
            save()
        }
        return false
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

nonisolated extension TransportError {
    /// The server didn't take it but may later: out of reach, down, or the session not ready yet. Anything else is
    /// its answer, and sending the same request again gets the same one.
    var isWorthRetrying: Bool {
        switch self {
        case .network, .maintenance: true
        case .status(let code): code >= 500 || code == 429 || code == 408
        case .api(let error): error == .unauthorized || error == .unavailable
        case .encoding, .decoding: false
        }
    }
}
