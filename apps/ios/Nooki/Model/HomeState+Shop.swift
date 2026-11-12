import FeatureShop
import Foundation
import ShopInterface

extension HomeState: ShopHost {
    var storeIsMock: Bool { AppPayments.isMock }

    func isPlaced(_ itemID: String) -> Bool { decor.state.layout.isPlaced(itemID) }

    func launchValue(_ key: String) -> String? { UserDefaults.standard.string(forKey: key) }

    func makeItemPreview() -> any ItemPreview { ItemTurntable() }
}
