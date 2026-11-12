#if canImport(UIKit)
  import Design
  import SwiftUI
  import UIKit

  /// A game's poster art on the Us shelf: the couple's own cat on a warm scene with the game's prop.
  public struct GamePoster: View {
    public enum Game {
      case whoKnows
      case drawGuess
    }

    let game: Game
    let coat: String
    /// A bundled picture decoded to at most `maxPixels`.
    let thumbnail: (_ name: String, _ maxPixels: Int) -> UIImage?

    public init(
      game: Game, coat: String, thumbnail: @escaping (_ name: String, _ maxPixels: Int) -> UIImage?
    ) {
      self.game = game
      self.coat = coat
      self.thumbnail = thumbnail
    }

    public var body: some View {
      let hero = thumbnail("Hero-\(coat)", 768).map(Image.init(uiImage:))
      switch game {
      case .whoKnows:
        PosterScene(
          tone: .honey, framing: .closeUp, hero: hero, prop: .note(symbol: "questionmark"))
      case .drawGuess:
        let painting = thumbnail("Item_frame-landscape", 512)
          .map { PosterScene.Prop.clay(Image(uiImage: $0)) }
        PosterScene(tone: .rose, framing: .seated, hero: hero, prop: painting)
      }
    }
  }
#endif
