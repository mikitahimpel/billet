import Wire

extension HomeState {
    /// Opens what an Inbox row points at: a note or a drawing in Moments, the cat's sheet, the room for a plant,
    /// a shop item's sheet, or the Shop for an offer.
    func open(_ target: ActivityTarget) {
        switch target {
        case .note, .moments:
            tab = .moments
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
