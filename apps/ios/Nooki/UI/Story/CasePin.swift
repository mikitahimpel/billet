import Design
import FeatureStory
import StoryInterface
import SwiftUI
import UIKit

/// The case on the corkboard: one card for the case file, and one more for the souvenir once the ending has been
/// heard. Both open the case sheet.
enum CasePin {
    private static let caseID = UUID(uuidString: "5EC4E71F-0000-4000-8000-000000000001")!
    private static let souvenirID = UUID(uuidString: "5EC4E71F-0000-4000-8000-000000000002")!

    static func owns(_ id: UUID) -> Bool { id == caseID || id == souvenirID }

    static func count(_ state: CaseMachine.State) -> Int {
        guard let book = state.book else { return 0 }
        return book.progress.isSolved ? 2 : 1
    }

    /// What shows on the cards, so a change redraws them.
    static func key(_ state: CaseMachine.State) -> [String] {
        guard let book = state.book else { return [] }
        return ["case \(book.episode.id) \(line(book))"]
    }

    @MainActor
    static func pins(_ state: CaseMachine.State, cat: String, partner: String) -> [BoardPin] {
        guard let book = state.book else { return [] }
        var pins = [pin(caseID, CaseFace(title: book.episode.title, line: Episode.filled(line(book), cat: cat, partner: partner), symbol: "magnifyingglass"))]
        if book.progress.isSolved {
            let souvenir = book.episode.souvenir
            pins.append(pin(souvenirID, CaseFace(title: souvenir.name, line: souvenir.note, symbol: souvenir.symbol)))
        }
        return pins.compactMap { $0 }
    }

    @MainActor
    private static func pin(_ id: UUID, _ face: CaseFace) -> BoardPin? {
        let renderer = ImageRenderer(content: face)
        renderer.scale = 2
        return renderer.uiImage.map { BoardPin(id: id, face: $0, size: [0.12, 0.12]) }
    }

    private static func line(_ book: CaseMachine.Book) -> String {
        let progress = book.progress
        switch progress.stage {
        case .clues:
            return progress.beats.contains { $0.isWaiting } ? "Something is different in the room." : "{cat} is working on it."
        case .naming: return "Who has it? Name a suspect."
        case .named: return "Waiting for {partner}'s answer."
        case .readyToTell: return "Both answers are in."
        case .told: return "Case closed."
        }
    }
}

private struct CaseFace: View {
    let title: String
    let line: String
    let symbol: String

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: symbol).font(.ourioLargeTitle)
            Text(title).font(.ourioHeadline).multilineTextAlignment(.center)
            Text(line).font(.ourioCaption).multilineTextAlignment(.center)
        }
        .foregroundStyle(Ink.heroInk)
        .padding(Space.l)
        .frame(width: 240)
        .aspectRatio(1, contentMode: .fit)
        .background(Ink.paper)
    }
}
