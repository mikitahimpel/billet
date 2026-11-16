import FeatureShop
import Foundation
import ShopInterface
import Wire

extension HomeState {
    /// Opens what an Inbox row points at: the note, the photo or the drawing itself in Moments (or Moments, when this
    /// phone doesn't have it), the cat's sheet, the room for a plant, a shop item's sheet (the Notes shelf for a stamp
    /// or seal), the Shop for an offer, or a list.
    /// A note or photo this phone doesn't have yet is opened by `openAwaited` once it lands.
    func open(_ target: ActivityTarget) {
        awaitedTarget = nil
        switch target {
        case .note(let id):
            tab = .moments
            if let note = notes.note(noteID: id.rawValue) {
                openedPin = PinRoute(id: note.id)
            } else {
                awaitedTarget = target
            }
        case .moments(let id):
            tab = .moments
            if let moment = moments.moments.first(where: { $0.noteID == id.rawValue }) {
                openedPin = PinRoute(id: moment.id)
            } else if let note = notes.note(noteID: id.rawValue) {
                openedPin = PinRoute(id: note.id)
            } else {
                awaitedTarget = target
            }
        case .cat:
            tab = .world
            showsPetSheet = true
        case .plant:
            tab = .world
        case .shopItem(let id):
            tab = .shop
            if NotePostage.all.contains(where: { $0.id == id }) {
                shopCategory = .notes
            } else {
                openedShopItem = Catalog.item(id, cat: petName)
            }
        case .shopOffer:
            tab = .shop
        case .list(let id):
            tab = .us
            usRoute = UUID(id).flatMap { us.list($0) == nil ? nil : .list($0) }
        }
    }

    /// True while an Inbox row waits for its note or photo to arrive.
    var awaitsTarget: Bool { awaitedTarget != nil }

    /// Opens the awaited row's note or photo if it has arrived; leaving Moments first drops it.
    func openAwaited() {
        guard let target = awaitedTarget else { return }
        guard tab == .moments else { return awaitedTarget = nil }
        open(target)
    }
}
