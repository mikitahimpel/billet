import OurioShared
import Testing
@testable import Billet

@Suite struct DateCatalogTests {
    @Test func theBuildShipsEveryIdea() throws {
        let catalog = try #require(DateCatalog.bundled)
        #expect(catalog.ideas.count == 150)
        #expect(Set(catalog.ideas.map(\.id)).count == catalog.ideas.count)
    }

    @Test func noTwoIdeasShareAPicture() throws {
        let ideas = try #require(DateCatalog.bundled).ideas
        #expect(Set(ideas.map(\.art.path)).count == ideas.count)
    }
}
