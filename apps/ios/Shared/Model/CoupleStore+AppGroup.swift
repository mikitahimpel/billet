import Foundation
import Persistence
import ProfileInterface

extension CoupleStore {
    private static let file = "Couple/couple.json"

    /// The couple as last saved, for a reader without a store such as the notification extension.
    public nonisolated static func saved() -> Couple? { SharedFile.read(Couple.self, from: file) }

    /// The App Group file the app, the widgets and the intents share.
    public convenience init() {
        self.init(
            load: { SharedFile.read(Couple.self, from: Self.file) },
            save: { SharedFile.write($0, to: Self.file) },
            photoURL: { SharedFile.url("Couple/photo-\($0).jpg") }
        )
        // A starter couple saved by init reaches the widgets before they next read it.
        SharedFile.flush()
    }
}
