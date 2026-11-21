import Foundation
import Payments
import PaymentsLive
import ServerSync
import Transport

// BILLET_PAYMENTS picks the store when the app is built (docs/payments.md). The target turns it into PAYMENTS_MOCK,
// PAYMENTS_STOREKIT or PAYMENTS_NONE, and Package.swift links only the matching store, if any, into PaymentsLive. Each
// branch names a type that exists in its own mode only, so an app and a package resolved for different modes fail to
// build.
#if PAYMENTS_STOREKIT
private typealias Build = StoreKitPaymentsBuild
#elseif PAYMENTS_MOCK
private typealias Build = MockPaymentsBuild
#elseif PAYMENTS_NONE
private typealias Build = NoPaymentsBuild
#else
#error("BILLET_PAYMENTS must be none, mock or storekit.")
#endif

enum AppPayments {
    /// A mock build fakes the store and only the dev server credits it. Either build sells coin packs only once the
    /// server turned the `payments` flag on (`CoinPacksModel.sells`).
    #if PAYMENTS_MOCK
    nonisolated static let isMock = true
    #else
    nonisolated static let isMock = false
    #endif

    /// The build's store over the pair's purchase routes, listening for transactions from launch on; nil in a `none`
    /// build.
    static func make(_ client: PurchasesClient) -> (any Payments)? {
        let live = Build.make(server: .live(client), defaults: .standard)
        live.start()
        return live.payments
    }
}
