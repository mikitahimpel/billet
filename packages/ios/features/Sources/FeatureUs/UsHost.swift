import Foundation
import MomentsInterface
import Persistence
import ProfileInterface
import SwiftUI
import Transport
import UsInterface
import WidgetBridge
import Wire

#if canImport(UIKit)
  import UIKit

  /// What the Us tab asks of the app that shows it: the couple and its stores, and the few things only the app
  /// can do. `HomeState` conforms.
  public protocol UsHost: AnyObject {
    var viewer: String { get }
    var otherPartner: String { get }
    var partners: (String, String) { get }
    var daysTogether: Int { get }
    var togetherSince: Date { get }
    var profile: CoupleStore { get }
    var us: UsStore { get }
    var moments: MomentStore { get }
    var streak: StreakStore { get }
    var remoteFlags: RemoteFlags { get }
    /// Which sheet the Us tab shows; widgets and links set it.
    var usRoute: UsView.Route? { get set }
    /// The couple's cat as the posters and the match cards draw it.
    var coatName: String { get }
    var coatAvatarName: String { get }

    /// A bundled picture decoded to at most `maxPixels`.
    func thumbnail(_ name: String, _ maxPixels: Int) -> UIImage?
    /// Adds a photo to the moments, as the journal does; false when it could not be kept.
    func addMoment(_ image: UIImage, caption: String, shares: Bool) -> Bool
    func refreshGifts() async
    /// The Games shelf, which the games themselves provide.
    func gamesSection() -> AnyView
    func gameScreen(_ game: UsGame) -> AnyView
  }

  public enum UsGame {
    case whoKnows, drawGuess
  }

  /// The phone's place on the server, which the Us tab uses for the pair, the games and the title search.
  public protocol UsServer: AnyObject {
    var api: APIClient { get }
    var baseURL: URL { get }
    var isPaired: Bool { get }
    /// The anonymous sign-in has finished, so pairing can start.
    var hasFinishedSignIn: Bool { get }
    var titles: TitleSource? { get }
    var pickTonight: PickTonightSync? { get }
    /// Set by the open Pick tonight screen; nil while it is closed.
    var matches: (@MainActor (PickMatch) -> Void)? { get set }
    /// The sheet that pairs this phone with the partner.
    func pairingSheet() -> AnyView
  }

  extension EnvironmentValues {
    @Entry public var usServer: (any UsServer)?
  }
#endif
