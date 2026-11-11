import AppIntents
import MomentsInterface
import MoodInterface
import OurioShared
import Persistence
import ProfileInterface
import UsInterface
import WidgetKit

// One-tap actions on the widgets and controls. They live in both the app and the extension: the system runs the app's
// copy when the app is in memory, the extension's otherwise. Either way they only touch the shared stores, and the app
// reloads those when it comes back.

/// Stores coalesce their writes; an intent's process may exit right after it returns, so write them out first.
@MainActor
private func savedReloadingWidgets() {
    SharedFile.flush()
    WidgetCenter.shared.reloadAllTimelines()
}

/// `PartnerMood` as an intent parameter: App Intents' metadata takes only enums declared in the target.
nonisolated enum MoodChoice: String, AppEnum {
    case happy, sleepy, missing, busy

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mood"
    static let caseDisplayRepresentations: [MoodChoice: DisplayRepresentation] = [
        .happy: "😊 Happy", .sleepy: "😴 Sleepy", .missing: "🥺 Missing you", .busy: "📚 Busy",
    ]

    init(_ mood: PartnerMood) {
        switch mood {
        case .happy: self = .happy
        case .sleepy: self = .sleepy
        case .missing: self = .missing
        case .busy: self = .busy
        }
    }

    var mood: PartnerMood {
        switch self {
        case .happy: .happy
        case .sleepy: .sleepy
        case .missing: .missing
        case .busy: .busy
        }
    }
}

/// Mochi purrs: the widget shows it right away, the app plays it on its next launch.
nonisolated struct PetMochiIntent: AppIntent {
    static let title: LocalizedStringResource = "Pet Your Cat"

    @MainActor
    func perform() async throws -> some IntentResult {
        var activity = WidgetActivity.load()
        activity.pet()
        activity.save()
        savedReloadingWidgets()
        return .result()
    }
}

/// Leaves a check-in for the partner holding the phone.
struct SetMoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Mood"
    static let isDiscoverable = false

    @Parameter(title: "Mood") var mood: MoodChoice

    init() {}

    init(_ mood: PartnerMood) {
        self.mood = MoodChoice(mood)
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        MoodStore().set(mood.mood, for: CoupleStore().couple.viewer)
        savedReloadingWidgets()
        return .result()
    }
}

/// Tells the partner "I'm thinking of you": a Missing-you check-in, the one mood that says it. It reaches them when the
/// app next runs, like any check-in made on a widget.
struct SendHugIntent: AppIntent {
    static let title: LocalizedStringResource = "Send a Hug"
    static let description = IntentDescription("Lets your partner know you are thinking of them.")

    @MainActor
    func perform() async throws -> some IntentResult {
        MoodStore().set(.missing, for: CoupleStore().couple.viewer)
        savedReloadingWidgets()
        return .result()
    }
}

/// Ticks a list item on or off. Carries the state to set rather than toggling, so a double tap can't undo itself.
struct SetListItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Tick List Item"
    static let isDiscoverable = false

    @Parameter(title: "List") var listID: String
    @Parameter(title: "Item") var itemID: String
    @Parameter(title: "Done") var done: Bool

    init() {}

    init(listID: UUID, itemID: UUID, done: Bool) {
        self.listID = listID.uuidString
        self.itemID = itemID.uuidString
        self.done = done
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let list = UUID(uuidString: listID), let item = UUID(uuidString: itemID) {
            UsStore().setItem(item, in: list, done: done)
            savedReloadingWidgets()
        }
        return .result()
    }
}

/// Draws a date idea for the widget: matches first, nothing planned lately, never the same one twice in a row.
nonisolated struct SurpriseIdeaIntent: AppIntent {
    static let title: LocalizedStringResource = "Surprise Us"

    @MainActor
    func perform() async throws -> some IntentResult {
        var activity = WidgetActivity.load()
        activity.ideaID = UsStore().randomIdea(filter: DateFilter(), excluding: Set([activity.ideaID].compactMap { $0 }))?.id
        activity.save()
        savedReloadingWidgets()
        return .result()
    }
}

/// Opens Ourio on a blank note, so a Lock Screen tap lands in the composer.
nonisolated struct NewNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New Note"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(DeepLink.newNote.url))
    }
}
