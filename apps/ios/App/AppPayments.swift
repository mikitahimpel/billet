import FeatureHome
import Foundation
import Payments
import PaymentsLive

// BILLET_PAYMENTS picks the store when the app is built (docs/payments.md). The app target turns
// it into PAYMENTS_MOCK or PAYMENTS_STOREKIT, and Package.swift links only the matching
// implementation into PaymentsLive. Each branch names a type that exists only in its own mode, so
// an app and a package resolved for different modes fail to build instead of shipping a mix.
#if PAYMENTS_STOREKIT
  private typealias Build = StoreKitPaymentsBuild
#elseif PAYMENTS_MOCK
  #if DISTRIBUTION_APPSTORE
    #error("An App Store build must sell through StoreKit: build it with BILLET_PAYMENTS=storekit.")
  #endif
  private typealias Build = MockPaymentsBuild
#else
  #error("BILLET_PAYMENTS must be mock or storekit.")
#endif

enum AppPayments {
  /// The build's store over `server`, listening for transactions from launch on.
  @MainActor
  static func make(server: PaymentsServer) -> DemoPayments {
    let live = Build.make(server: server, defaults: .standard)
    live.start()
    return DemoPayments(payments: live.payments, labs: live.labs)
  }
}
