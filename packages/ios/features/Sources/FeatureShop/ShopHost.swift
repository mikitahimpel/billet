import Foundation
import ShopInterface
import WidgetBridge

/// What the Shop asks of the app that shows it: its store, where it opens, the cat's name, and the
/// two things only the room can answer. `HomeState` conforms.
public protocol ShopHost: AnyObject {
  var shop: ShopModel { get }
  var shopCategory: ShopCategory { get set }
  var shopFocus: ShopFocus? { get set }
  var petName: String { get }
  var remoteFlags: RemoteFlags { get }
  /// The cat's avatar picture, by the coat it wears.
  var coatAvatarName: String { get }
  /// A mock store fakes coin packs: the Coins sheet says so.
  var storeIsMock: Bool { get }
  /// True when the room has the piece standing in it.
  func isPlaced(_ itemID: String) -> Bool
  /// Opens the World with its pieces arranged, `item` chosen when given.
  func decorate(_ item: String?)
  /// The 3D turntable of one item sheet.
  func makeItemPreview() -> any ItemPreview
  /// A launch argument that picks what the Shop opens at, for screenshots and UI tests (Debug builds).
  func launchValue(_ key: String) -> String?
}

extension ShopHost {
  func decorate() { decorate(nil) }
}
