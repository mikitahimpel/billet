import Design
import FeatureUs
import SwiftUI
import UsInterface

/// The Us tab's Games shelf: a poster for each game, which opens the game's sheet.
struct UsGamesSection: View {
    let state: HomeState

    @Environment(ServerSession.self) private var session: ServerSession?
    /// The round for a build without a server, which has no partner to play with.
    @State private var unpaired = WhoKnowsModel(sync: nil, viewer: nil, catalog: [])
    @State private var unpairedRiddles = DrawGuessModel(sync: nil, viewer: nil, words: .bundled)
    @Environment(\.dynamicTypeSize) private var typeSize

    private var whoKnows: WhoKnowsModel { session?.whoKnows ?? unpaired }
    private var drawGuess: DrawGuessModel { session?.drawGuess ?? unpairedRiddles }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("Games")
            let partner = state.profile.name(of: state.otherPartner)
            let posters = Group {
                let whoKnowsStatus = WhoKnowsModel.status(whoKnows.phase, remaining: whoKnows.remaining,
                                                          partner: partner)
                PosterCard("Who knows who", status: whoKnowsStatus, emphasis: whoKnows.phase == .revealed,
                           action: { state.usRoute = .whoKnows }) {
                    GamePoster(game: .whoKnows, coat: state.coatName, thumbnail: state.thumbnail)
                }
                PosterCard("Draw & guess", status: drawGuessStatus(partner: partner),
                           emphasis: drawGuess.phase == .guess, action: { state.usRoute = .drawGuess }) {
                    GamePoster(game: .drawGuess, coat: state.coatName, thumbnail: state.thumbnail)
                }
            }
            if typeSize.isAccessibilitySize {
                VStack(spacing: Space.m) { posters }
            } else {
                // Three fifths of the width each, so the next poster peeks in from the edge.
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: Space.m) {
                        posters.containerRelativeFrame(.horizontal, count: 5, span: 3, spacing: Space.m)
                    }
                    // Each poster as tall as its art and words, not the height the scroll view offers.
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
        .task(id: session?.isPaired) {
            await whoKnows.load()
            await drawGuess.load()
        }
    }

    private func drawGuessStatus(partner: String) -> String {
        DrawGuessModel.status(drawGuess.phase, partner: partner,
                              letters: drawGuess.theirs?.shape.reduce(0, +) ?? 0, lastEnded: drawGuess.lastEnded,
                              endedMine: drawGuess.lastEnded.map(drawGuess.isMine) ?? false)
    }
}

/// A game's sheet over the Us tab.
struct UsGameScreen: View {
    let state: HomeState
    let game: UsGame

    @Environment(ServerSession.self) private var session: ServerSession?
    @State private var unpaired = WhoKnowsModel(sync: nil, viewer: nil, catalog: [])
    @State private var unpairedRiddles = DrawGuessModel(sync: nil, viewer: nil, words: .bundled)

    var body: some View {
        switch game {
        case .whoKnows: WhoKnowsScreen(state: state, model: session?.whoKnows ?? unpaired)
        case .drawGuess: DrawGuessScreen(state: state, model: session?.drawGuess ?? unpairedRiddles)
        }
    }
}
