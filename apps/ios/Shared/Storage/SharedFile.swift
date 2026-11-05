import Foundation

/// JSON files inside the app group, written atomically because the app and the widget extension share them.
///
/// Writes are coalesced: the latest value per path is encoded and written on a background queue a moment later.
/// Call `flush()` before anything outside this process reads the files: intents before they return, the app before
/// it reloads the widgets.
nonisolated enum SharedFile {
    static let delay: DispatchTimeInterval = .milliseconds(400)

    private static let queue = DispatchQueue(label: "com.mikitahimpel.billet.shared-file", qos: .utility)
    /// Latest unwritten value per path. Only touched on `queue`.
    nonisolated(unsafe) private static var pending: [String: (id: UUID, write: @Sendable () -> Void)] = [:]

    static func url(_ path: String) -> URL { AppGroup.container.appending(path: path) }

    /// Sees this process's own pending write to `path` too. A file that is there but won't decode (cut short, or
    /// written in a shape this build doesn't know) moves to `<path>.unreadable` first, so the store's next save of its
    /// defaults doesn't overwrite what it held.
    static func read<Value: Decodable>(_ type: Value.Type, from path: String) -> Value? {
        queue.sync { writePending(path) }
        let file = url(path)
        guard let data = try? Data(contentsOf: file) else { return nil }
        if let value = try? JSONDecoder().decode(type, from: data) { return value }
        let aside = file.appendingPathExtension("unreadable")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: file, to: aside)
        return nil
    }

    static func write(_ value: some Encodable & Sendable, to path: String) {
        let id = UUID()
        queue.async {
            pending[path] = (id, { store(value, at: path) })
            queue.asyncAfter(deadline: .now() + delay) {
                if pending[path]?.id == id { writePending(path) }
            }
        }
    }

    /// Writes everything still pending before returning.
    static func flush() {
        queue.sync {
            for path in Array(pending.keys) { writePending(path) }
        }
    }

    private static func writePending(_ path: String) {
        guard let job = pending.removeValue(forKey: path) else { return }
        job.write()
    }

    private static func store(_ value: some Encodable, at path: String) {
        let target = url(path)
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(value).write(to: target, options: .atomic)
    }
}
