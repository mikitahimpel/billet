import Design
import SwiftUI

/// A game's poster art on the Us shelf: the couple's own cat on a warm scene with the game's prop.
struct GamePoster: View {
    enum Game {
        case whoKnows
        case drawGuess
    }

    let game: Game
    var coat: CatCoat = .current()

    var body: some View {
        let hero = Thumbnails.image("Hero-\(coat.rawValue)", maxPixels: 768).map(Image.init(uiImage:))
        switch game {
        case .whoKnows:
            PosterScene(tone: .honey, framing: .closeUp, hero: hero, prop: .note(symbol: "questionmark"))
        case .drawGuess:
            let painting = Thumbnails.image("Item_frame-landscape", maxPixels: 512).map { PosterScene.Prop.clay(Image(uiImage: $0)) }
            PosterScene(tone: .rose, framing: .seated, hero: hero, prop: painting)
        }
    }
}
