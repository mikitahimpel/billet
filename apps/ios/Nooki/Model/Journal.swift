import MomentsInterface
import Observation
import WidgetInterface
import WidgetUI
import ProfileInterface
import UIKit
import UsInterface
import Wire

/// What the couple adds to Moments and the board. The server pays for each: a photo or text note that goes to the
/// partner earns when it arrives there, and anything that stays on this phone is reported as an earn.
@Observable
final class Journal {
    @ObservationIgnored private let moments: MomentStore
    @ObservationIgnored private let notes: NoteStore
    @ObservationIgnored private let streak: StreakStore
    @ObservationIgnored private let couple: CoupleStore
    @ObservationIgnored private let earn: (EarnEvent) -> Void

    init(
        moments: MomentStore, notes: NoteStore, streak: StreakStore, couple: CoupleStore,
        earn: @escaping (EarnEvent) -> Void
    ) {
        self.moments = moments
        self.notes = notes
        self.streak = streak
        self.couple = couple
        self.earn = earn
    }

    private var viewer: String { couple.couple.viewer }

    /// A photo that `shares` also goes to the partner once this phone is paired (`PhotoSync`), and earns there; a
    /// drawing's keepsake does not, as the drawing went already, so it earns as a moment.
    @discardableResult
    func addMoment(_ image: UIImage, caption: String, shares: Bool = false) -> Bool {
        guard let moment = moments.add(image, caption: caption, author: viewer, unsent: shares) else { return false }
        if !shares { earn(.momentAdded(moment: moment.id.uuidString)) }
        streak.record()
        return true
    }

    /// A text note always goes to the partner (`TextNoteSync`), so the server pays for it when it arrives.
    @discardableResult
    func addNote(
        text: String, paper: Note.Paper, ink: UInt32? = nil, stamp: NoteStamp? = nil, seal: NoteSeal? = nil
    ) -> Bool {
        guard notes.add(text: text, paper: paper, author: viewer, ink: ink, stamp: stamp, seal: seal) != nil
        else { return false }
        streak.record()
        return true
    }

    /// A doodle stays on this phone, so it earns as a note.
    @discardableResult
    func addNote(doodle: UIImage, paper: Note.Paper, stamp: NoteStamp? = nil, seal: NoteSeal? = nil) -> Bool {
        guard let note = notes.add(doodle: doodle, paper: paper, author: viewer, stamp: stamp, seal: seal)
        else { return false }
        earn(.noteAdded(note: note.id.uuidString))
        streak.record()
        return true
    }
}
