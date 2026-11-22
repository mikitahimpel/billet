import FeatureMischief
import Foundation
import ProfileInterface
import Transport
import Wire

extension MischiefModel.Storage {
    /// The ledger as JSON in the user defaults: a mouse waits longer than the journal is read.
    static func defaults(_ defaults: UserDefaults = .standard, key: String = "mischief.ledger") -> Self {
        .init(
            load: { defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(MischiefLedger.self, from: $0) } },
            save: { defaults.set(try? JSONEncoder().encode($0), forKey: key) })
    }
}

extension MischiefModel {
    /// Plays through the pair's journal in `catLife`. The room's hints are wired by Home once it has a room.
    static func live(profile: CoupleStore, events: EventReporter, catLife: CatLife = CatRoom.catLife) -> MischiefModel {
        let model = MischiefModel(
            pair: { profile.couple.catPair.map { .init(me: $0.me, partner: $0.partner) } },
            storage: .defaults(),
            record: { events in catLife.record(events).map { Optional($0) } })
        model.played = { played in
            switch played {
            case .hid: events(.mouseHidden)
            case .found: events(.mouseFound)
            }
        }
        catLife.onEntry = { [weak model] entry in model?.receive(entry) }
        catLife.onReset = { [weak model] in model?.forget() }
        return model
    }
}
