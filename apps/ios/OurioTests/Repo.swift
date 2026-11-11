import Foundation

enum Repo {
    /// The checkout under test. A build that shares the compilation cache maps source paths to fixed names, so a
    /// cached `#filePath` can name another worktree; scripts/verify-ios.sh passes the real one as BILLET_REPO.
    static let root: URL = ProcessInfo.processInfo.environment["BILLET_REPO"].map { URL(fileURLWithPath: $0) }
        ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
}
