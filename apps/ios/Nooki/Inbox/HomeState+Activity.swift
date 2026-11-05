import Wire

extension HomeState {
    /// Opens what an Inbox row points at: the note or the photo itself in Moments (or Moments, when this phone doesn't
    /// have it), the cat's sheet, the room for a plant, a shop item's sheet, or the Shop for an offer.
    func open(_ target: ActivityTarget) {
        switch target {
        case .note(let id):
            tab = .moments
            if let note = notes.note(noteID: id.rawValue) { openedPin = PinRoute(id: note.id) }
        case .moments(let id):
            tab = .moments
            if let moment = moments.moments.first(where: { $0.noteID == id.rawValue }) {
                openedPin = PinRoute(id: moment.id)
            }
        case .cat:
            tab = .world
            showsPetSheet = true
        case .plant:
            tab = .world
        case .shopItem(let id):
            tab = .shop
            openedShopItem = Catalog.item(id)
        case .shopOffer:
            tab = .shop
        }
    }
}
