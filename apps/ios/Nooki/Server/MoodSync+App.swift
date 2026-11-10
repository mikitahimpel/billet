import FeatureMood
import MoodInterface
import OurioShared
import Transport
import Wire

extension MoodSync {
    /// The couple's check-ins kept in the App Group's `MoodStore`, under the pair's monograms.
    init(send: @escaping Send, moods: MoodStore, couple: CoupleStore) {
        self.init(
            send: send, moods: moods, viewer: { couple.couple.viewer },
            monogram: { user in couple.couple.pair?.users.first { $0.value == user.rawValue }?.key })
    }
}
