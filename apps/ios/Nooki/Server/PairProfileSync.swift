import Foundation
import ProfileInterface
import Transport
import Wire

/// The partners' names and the pair's day, between the couple on this phone and the server. A failed send is
/// tried again on the next pull, which finds the server still differing.
@MainActor
enum PairProfileSync {
    /// Takes the pair's profile into `profile` and sends back what the server lacks.
    static func take(_ pair: PairResponse, into profile: CoupleStore, api: APIClient) async {
        let server = PairProfile(
            myName: pair.name(of: pair.members[0]), partnerName: pair.name(of: pair.members[1]),
            togetherSince: pair.togetherSince.flatMap { PairProfile.date(localDay: $0) },
            pairedAt: pair.pairedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) })
        await send(profile.take(server), api: api)
    }

    /// After the holder saved the profile editor: their own name and the pair's day, for the partner.
    static func edited(_ profile: CoupleStore, api: APIClient) async {
        let couple = profile.couple
        guard couple.pair != nil else { return }
        await send([.name(PairProfile.displayName(couple.names?[couple.viewer])),
                    .day(couple.togetherSince, ifUnset: false)], api: api)
    }

    private static func send(_ pushes: [PairProfile.Push], api: APIClient) async {
        for push in pushes {
            switch push {
            case .name(let name):
                try? await api.setDisplayName(SetDisplayNameRequest(displayName: name))
            case .day(let day, let ifUnset):
                try? await api.setTogetherSince(
                    SetTogetherSinceRequest(day: PairProfile.localDay(day), ifUnset: ifUnset ? true : nil))
            }
        }
    }
}
