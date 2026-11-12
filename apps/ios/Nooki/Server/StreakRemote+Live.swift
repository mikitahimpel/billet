import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import Transport
import UsInterface
import Wire

extension StreakRemote {
    /// `/v1/streak` over `http`.
    /// `you`: this phone's member, to tell its marks from the partner's.
    static func live(http: HTTPService, token: @escaping @Sendable () async -> String?,
                     you: @escaping @Sendable () -> String?, calendar: Calendar = .current) -> StreakRemote {
        @Sendable func call(_ request: HTTPRequest) async -> Answer {
            guard let token = await token() else { return .offline }
            var request = request
            request.headers[Routes.authorizationHeader] = Routes.bearerPrefix + token
            do throws(TransportError) {
                let response = try await http.perform(request, as: StreakResponse.self)
                return .streak(LoveStreak(response.streak, you: you(), calendar: calendar))
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
