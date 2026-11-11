import AppIntents
import MomentsInterface
import WidgetInterface
import WidgetUI
import UsInterface
import WidgetKit

/// A block picked in "Edit Widget": a fixed module, or the smart slot that picks one by itself.
enum WidgetSlot: String, AppEnum {
    case smart, mochi, us, mood, list, date, moment

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Block"
    static let caseDisplayRepresentations: [WidgetSlot: DisplayRepresentation] = [
        .smart: "✦ Smart", .mochi: "Cat", .us: "Together", .mood: "Mood",
        .list: "List", .date: "Date", .moment: "Moment",
    ]

    func module(in snapshot: OurioSnapshot) -> WidgetModule {
        WidgetModule(rawValue: rawValue) ?? snapshot.smartModule
    }
}

/// One of the couple's lists, for the List module.
struct ListEntity: AppEntity {
    let id: UUID
    let title: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static let defaultQuery = ListQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct ListQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ListEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ListEntity] { all() }

    private func all() -> [ListEntity] {
        UsStore().lists.map { ListEntity(id: $0.id, title: $0.title) }
    }
}

protocol OurioConfiguration: WidgetConfigurationIntent {
    /// The list the List module shows; nil picks the groceries list.
    var listID: UUID? { get }
}

struct ModuleConfiguration: OurioConfiguration {
    static let title: LocalizedStringResource = "Block"

    @Parameter(title: "Block", default: .smart) var first: WidgetSlot
    @Parameter(title: "Second block (medium)", default: .date) var second: WidgetSlot
    @Parameter(title: "List") var list: ListEntity?

    var listID: UUID? { list?.id }
}
