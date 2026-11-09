import Foundation

/// What happened on the widgets and controls while the app was closed: pets waiting to reach Mochi and the date idea
/// the widget last drew.
public nonisolated struct WidgetActivity: Codable, Hashable, Sendable {
    public var lastPet: Date?
    /// Pets from outside the app that Mochi hasn't felt yet; the app takes them on its next launch.
    public var pendingPets = 0
    public var ideaID: Int?

    public init(lastPet: Date? = nil, pendingPets: Int = 0, ideaID: Int? = nil) {
        self.lastPet = lastPet
        self.pendingPets = pendingPets
        self.ideaID = ideaID
    }

    /// How long the widget shows Mochi purring after a pet.
    public static let purrLength: TimeInterval = 60

    private static let file = "Couple/widget-activity.json"

    public static func load() -> WidgetActivity { SharedFile.read(WidgetActivity.self, from: file) ?? WidgetActivity() }

    public func save() { SharedFile.write(self, to: Self.file) }

    public func isPurring(at date: Date) -> Bool {
        guard let lastPet else { return false }
        return date >= lastPet && date < lastPet.addingTimeInterval(Self.purrLength)
    }

    public mutating func pet(at date: Date = .now) {
        lastPet = date
        pendingPets += 1
    }

    public mutating func takePendingPets() -> Int {
        defer { pendingPets = 0 }
        return pendingPets
    }
}
