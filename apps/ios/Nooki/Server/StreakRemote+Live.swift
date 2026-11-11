import Foundation
import MomentsInterface
import OurioShared
import Transport
import UsInterface
import Wire

extension StreakRemote {
    /// `/v1/streak` over `http`.
    static func live(http: HTTPService, token: @escaping @Sendable () async -> String?,
                     calendar: Calendar = .current) -> StreakRemote {
        @Sendable func call(_ request: HTTPRequest) async -> Answer {
            guard let token = await token() else { return .offline }
            var request = request
            request.headers[Routes.authorizationHeader] = Routes.bearerPrefix + token
            do throws(TransportError) {
                let response = try await http.perform(request, as: StreakResponse.self)
                return .streak(LoveStreak(response.streak, calendar: calendar))
            } catch {
                return answer(to: error)
            }
        }
        @Sendable func post(_ route: Route, _ body: some Encodable & Sendable) async -> Answer {
            do throws(TransportError) {
                return await call(try HTTPRequest.json(route.method, path: route.path, body: body))
            } catch {
                return answer(to: error)
            }
        }
        return StreakRemote(
            load: { await call(HTTPRequest(method: Routes.getStreak.method, path: Routes.getStreak.path)) },
            record: { at in
                let offset = TimeZone.current.secondsFromGMT(for: at)
                return await post(
                    Routes.recordStreakDay,
                    RecordStreakDayRequest(at: Int(at.timeIntervalSince1970 * 1000), utcOffsetSeconds: offset))
            },
            restore: {
                await post(Routes.restoreStreak, RestoreStreakRequest(utcOffsetSeconds: TimeZone.current.secondsFromGMT()))
            })
    }

    /// A drop, a server that is down or a lost session may pass, so what waits is tried again; anything else the
    /// room answered is final.
    static func answer(to error: TransportError) -> Answer {
        switch error {
        case .network, .status, .maintenance, .api(.unavailable), .api(.unauthorized): .offline
        case .decoding, .encoding, .api(.streakNotRestorable), .api(.notFound), .api(.invalidRequest),
             .api(.invalidInvite), .api(.alreadyPaired), .api(.appleIdInUse), .api(.invalidPurchase), .api(.inkNotOwned),
             .api(.notEnoughCoins), .api(.alreadyOwned), .api(.collectionIncomplete), .api(.giftTaken),
             .api(.bonusTaken), .api(.catNotAdopted), .api(.priceChanged), .api(.layoutRefused):
            .refused
        }
    }
}

extension LoveStreak {
    /// The room's streak in this phone's days: each local day is the start of that day in `calendar`.
    init(_ wire: PairStreak, calendar: Calendar = .current) {
        self.init(count: wire.days, lastDay: wire.lastDay.flatMap { Self.day($0, calendar) }, best: wire.best,
                  lastRestore: wire.restoredOn.flatMap { Self.day($0, calendar) })
    }

    /// `YYYY-MM-DD` as the start of that day.
    static func day(_ text: String, _ calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
