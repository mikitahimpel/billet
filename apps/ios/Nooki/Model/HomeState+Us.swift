import FeatureUs
import MomentsInterface
import SwiftUI
import UIKit
import WidgetBridge
import WidgetUI

extension HomeState: UsHost {
    var remoteFlags: RemoteFlags { rooms.remote }
    var coatName: String { CatCoat.current().rawValue }
    var coatAvatarName: String { CatCoat.current().avatar }

    func addMoment(_ image: UIImage, caption: String, shares: Bool) -> Bool {
        journal.addMoment(image, caption: caption, shares: shares)
    }

    func thumbnail(_ name: String, _ maxPixels: Int) -> UIImage? { Thumbnails.image(name, maxPixels: maxPixels) }

    func refreshGifts() async { await gifts.refresh() }

    func gamesSection() -> AnyView { AnyView(UsGamesSection(state: self)) }

    func gameScreen(_ game: UsGame) -> AnyView { AnyView(UsGameScreen(state: self, game: game)) }
}
