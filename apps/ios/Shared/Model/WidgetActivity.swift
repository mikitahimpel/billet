import Foundation

/// What happened on the widgets and controls while the app was closed: pets waiting to reach Mochi and the date idea
/// the widget last drew.
nonisolated struct WidgetActivity: Codable, Hashable {
    var lastPet: Date?
    /// Pets from outside the app that Mochi hasn't felt yet; the app takes them on its next launch.
    var pendingPets = 0
    var ideaID: Int?

    /// How long the widget shows Mochi purring after a pet.
    static let purrLength: TimeInterval = 60

    private static let file = "Couple/widget-activity.json"

    static func load() -> WidgetActivity { SharedFile.read(WidgetActivity.self, from: file) ?? WidgetActivity() }

    func save() { SharedFile.write(self, to: Self.file) }

    func isPurring(at date: Date) -> Bool {
        guard let lastPet else { return false }
        return date >= lastPet && date < lastPet.addingTimeInterval(Self.purrLength)
    }

    mutating func pet(at date: Date = .now) {
        lastPet = date
        pendingPets += 1
    }

    mutating func takePendingPets() -> Int {
        defer { pendingPets = 0 }
        return pendingPets
    }
}
