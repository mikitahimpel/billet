import Foundation

/// The container the app and its widgets both read and write: every store keeps its files here.
public nonisolated enum AppGroup {
    public static let id = "group.com.ourio.app"

    /// Falls back to Documents when the build isn't signed with the group, so the app still works without widgets.
    public static let container: URL = {
        let documents = URL.documentsDirectory
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return documents }
        moveLegacyFolders(from: documents, to: group)
        return group
    }()

    /// Builds before the widgets kept their stores in the app's Documents; move them over once.
    private static func moveLegacyFolders(from documents: URL, to group: URL) {
        let files = FileManager.default
        for folder in ["Us", "Moments"] {
            let old = documents.appending(path: folder, directoryHint: .isDirectory)
            let new = group.appending(path: folder, directoryHint: .isDirectory)
            guard files.fileExists(atPath: old.path()), !files.fileExists(atPath: new.path()) else { continue }
            try? files.moveItem(at: old, to: new)
        }
    }
}
