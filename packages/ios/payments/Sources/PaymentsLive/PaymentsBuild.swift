import Foundation
import Payments
import SwiftUI

#if PAYMENTS_STOREKIT
  import PaymentsStoreKit
#elseif PAYMENTS_MOCK
  import PaymentsMock
#endif

/// Package.swift links at most one of `PaymentsStoreKit` or `PaymentsMock` into this target, from
/// `BILLET_PAYMENTS`.
public struct LivePayments: Sendable {
  /// Nil in a `none` build, which sells nothing.
  public let payments: (any Payments)?
  /// Labs → Payments, when this build has anything to show there.
  public let labs: (@MainActor @Sendable () -> AnyView)?
  private let begin: @Sendable () -> Void

  init(
    payments: (any Payments)?, labs: (@MainActor @Sendable () -> AnyView)?,
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
#elseif PAYMENTS_MOCK
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
#else
  /// Exists only in a `none` build: no store is linked, so nothing is sold and no transaction is
  /// read. The app names it, so a mix of modes fails to build.
  public enum NoPaymentsBuild {
    public static func make(server: PaymentsServer, defaults: UserDefaults) -> LivePayments {
      LivePayments(payments: nil, labs: nil, begin: {})
    }
  }
#endif
