import Foundation
import Transport
import Wire

/// Onboarding answers waiting for the server, kept in a file so a closed app or a phone without signal loses none.
///
/// Sent oldest first. An answer the server refuses as invalid (a step or option its catalogue no longer has) is
/// dropped; any other failure stops the round and keeps the rest for the next `flush`. The server keeps the answer
/// with the latest `answeredAt`, so sending one twice is harmless.
@MainActor
final class AnswerQueue {
    private(set) var pending: [SaveOnboardingAnswerRequest]
    private let file: URL
    private var flushing = false

    init(file: URL = AnswerQueue.defaultFile) {
        self.file = file
        pending = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([SaveOnboardingAnswerRequest].self, from: $0) } ?? []
    }

    static var defaultFile: URL {
        URL.applicationSupportDirectory.appending(path: "Onboarding/answers.json")
    }

    /// Replaces a waiting answer to the same step, since only the latest one counts.
    func add(_ request: SaveOnboardingAnswerRequest) {
        pending.removeAll { $0.stepId == request.stepId }
        pending.append(request)
        save()
    }

    /// Whether every waiting answer is now sent.
    @discardableResult
    func flush(with client: OnboardingClient) async -> Bool {
        guard !flushing else { return false }
        flushing = true
        defer { flushing = false }
        while let next = pending.first {
            do {
                try await client.save(next)
            } catch {
                guard error == .api(.invalidRequest) else { return false }
            }
            pending.removeAll { $0 == next }
            save()
        }
        return true
    }

    private func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(pending).write(to: file, options: .atomic)
    }
}
