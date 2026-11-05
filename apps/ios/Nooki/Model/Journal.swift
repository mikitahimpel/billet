import Observation
import UIKit

/// What the couple adds to Moments and the board. Each earns a few coins on a phone that keeps its own wallet; on a
/// synced pair the server pays for the photo or note when it arrives there.
@Observable
final class Journal {
    @ObservationIgnored private let moments: MomentStore
    @ObservationIgnored private let notes: NoteStore
    @ObservationIgnored private let wallet: WalletStore
    @ObservationIgnored private let streak: StreakStore
    @ObservationIgnored private let couple: CoupleStore

    init(moments: MomentStore, notes: NoteStore, wallet: WalletStore, streak: StreakStore, couple: CoupleStore) {
        self.moments = moments
        self.notes = notes
        self.wallet = wallet
        self.streak = streak
        self.couple = couple
    }

    private var viewer: String { couple.couple.viewer }

    /// Adding a moment earns the couple 10 coins (see docs/shop-concept.md). A photo that `shares` also goes to the
    /// partner once this phone is paired (`PhotoSync`); a drawing's keepsake does not, as the drawing went already.
    @discardableResult
    func addMoment(_ image: UIImage, caption: String, shares: Bool = false) -> Bool {
        guard moments.add(image, caption: caption, author: viewer, unsent: shares) != nil else { return false }
        wallet.earn(10)
        streak.record()
        return true
    }

    /// Adding a note earns the couple 5 coins.
    @discardableResult
    func addNote(text: String, paper: Note.Paper, ink: UInt32? = nil) -> Bool {
        guard notes.add(text: text, paper: paper, author: viewer, ink: ink) != nil else { return false }
        wallet.earn(5)
        streak.record()
        return true
    }

    @discardableResult
    func addNote(doodle: UIImage, paper: Note.Paper) -> Bool {
        guard notes.add(doodle: doodle, paper: paper, author: viewer) != nil else { return false }
        wallet.earn(5)
        streak.record()
        return true
    }
}
