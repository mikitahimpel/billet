import Foundation
import Payments
import SwiftUI

#if PAYMENTS_STOREKIT
  import PaymentsStoreKit
#else
  import PaymentsMock
#endif

/// Package.swift links only one of `PaymentsStoreKit` or `PaymentsMock` into this target, from
/// `BILLET_PAYMENTS`.
public struct LivePayments: Sendable {
  public let payments: any Payments
  /// Labs → Payments, when this build has anything to show there.
  public let labs: (@MainActor @Sendable () -> AnyView)?
  private let begin: @Sendable () -> Void

  init(
    payments: any Payments, labs: (@MainActor @Sendable () -> AnyView)?,
    begin: @escaping @Sendable () -> Void
  ) {
    self.payments = payments
    self.labs = labs
    self.begin = begin
  }

  /// Call once at launch.
  public func start() { begin() }
}

#if PAYMENTS_STOREKIT
  /// Exists only in a StoreKit build. The app names it, so an app compiled for one mode against a
  /// package resolved for the other fails to build.
  public enum StoreKitPaymentsBuild {
    public static func make(server: PaymentsServer, defaults: UserDefaults) -> LivePayments {
      let payments = StoreKitPayments(server: server)
      return LivePayments(payments: payments, labs: nil, begin: { payments.start() })
    }
  }
#else
  /// Exists only in a mock build. The app names it, so an app compiled for one mode against a
  /// package resolved for the other fails to build.
  public enum MockPaymentsBuild {
    public static func make(server: PaymentsServer, defaults: UserDefaults) -> LivePayments {
      let switches = MockSwitches.defaults(defaults)
      let payments = MockPayments(server: server, switches: switches)
      return LivePayments(
        payments: payments,
        labs: { AnyView(MockPaymentsLabsView(payments: payments, switches: switches)) },
        begin: {})
    }
  }
#endif
