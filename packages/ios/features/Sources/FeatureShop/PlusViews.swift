#if canImport(UIKit)
  import Design
  import Payments
  import ShopInterface
  import SwiftUI
  import WidgetUI
  import Wire

  /// Where Plus's legal and Apple's account pages are; the app has no cancel or refund flow of its own.
  public enum PlusLinks {
    static let terms = URL(string: "https://ourio.mikitahimpel.com/terms/")!
    static let privacy = URL(string: "https://ourio.mikitahimpel.com/privacy/")!
    public static let manage = URL(string: "https://apps.apple.com/account/subscriptions")!
    static let refund = URL(string: "https://reportaproblem.apple.com")!
  }

  /// The one row in the Shop and in Settings. Nothing about money: the price is only in the sheet.
  public struct PlusRow: View {
    let entry: PlusEntry
    let open: () -> Void

    public init(entry: PlusEntry, open: @escaping () -> Void) {
      self.entry = entry
      self.open = open
    }

    public var body: some View {
      if let line {
        Button(action: open) {
          Row(line.title, detail: line.detail, symbol: "shippingbox.fill", tint: .honey) {
            RowChevron()
          }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityIdentifier("plusRow")
      }
    }

    private var line: (title: String, detail: String)? {
      switch entry {
      case .hidden: nil
      case .offer: ("Ourio Plus", "A parcel every month")
      case .parcels(1): ("A parcel is here", "Choose something together")
      case .parcels(let count): ("\(count) parcels are here", "Choose something together")
      case .has: ("Ourio Plus", "On for the two of you")
      }
    }
  }

  /// Shown once after onboarding, while nothing from the partner waits; it never opens the sheet by itself.
  public struct PlusWelcomeCard: View {
    let open: () -> Void
    let dismiss: () -> Void

    public init(open: @escaping () -> Void, dismiss: @escaping () -> Void) {
      self.open = open
      self.dismiss = dismiss
    }

    public var body: some View {
      Card {
        VStack(alignment: .leading, spacing: Space.m) {
          HStack(alignment: .top, spacing: Space.m) {
            SymbolBadge(symbol: "shippingbox.fill", tint: .honey)
            VStack(alignment: .leading, spacing: Space.xs) {
              Text("Ourio Plus")
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
              Text(
                "If you'd like, a parcel every month for the two of you. Everything else stays free."
              )
              .font(.ourioCallout)
              .foregroundStyle(Ink.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: dismiss) {
              Image(systemName: "xmark")
                .font(.ourioCallout.weight(.semibold))
                .foregroundStyle(Ink.textSecondary)
                .frame(minWidth: Size.control, minHeight: Size.control)
                .contentShape(.rect)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Close")
            .accessibilityIdentifier("plusWelcomeClose")
          }
          SecondaryButton("Have a look", action: open)
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("plusWelcome")
    }
  }

  /// Ourio Plus: what it is and its price for a pair without it, the parcels for a pair with it.
  public struct PlusSheet: View {
    let model: PlusModel
    let shop: ShopModel
    let petName: String
    @State private var choosing = false

    public init(model: PlusModel, shop: ShopModel, petName: String) {
      self.model = model
      self.shop = shop
      self.petName = petName
    }

    public var body: some View {
      BilletSheet("Ourio Plus", size: .large) {
        VStack(alignment: .leading, spacing: Space.section) {
          switch model.state {
          case .idle, .loading:
            LoadingState()
          case .notOffered:
            EmptyState(
              symbol: "shippingbox", title: "Not here yet",
              text: "Ourio Plus isn't offered on this account.")
          case .unavailable:
            ErrorState("Couldn't reach Ourio", text: "Nothing was charged.") {
              model.send(PlusMachine.Event.retryTapped)
            }
          case .offered(let shelf), .buying(let shelf), .waiting(let shelf), .delivering(let shelf),
            .restoring(let shelf):
            parcels(shelf.plus)
            OfferView(model: model, shelf: shelf, petName: petName)
          case .mine(let plus):
            HasPlus(plus: plus, mine: true, petName: petName)
            parcels(plus)
          case .partners(let plus):
            HasPlus(plus: plus, mine: false, petName: petName)
            parcels(plus)
          }
        }
      }
      .accessibilityIdentifier("plusSheet")
      .sheet(
        isPresented: Binding(
          get: { choosing && model.parcel != .closed },
          set: { if !$0 { choosing = false } })
      ) {
        ParcelChooser(model: model, shop: shop, petName: petName)
      }
    }

    @ViewBuilder private func parcels(_ plus: PlusResponse) -> some View {
      if let first = plus.parcels.first {
        Card(warm: true) {
          VStack(alignment: .leading, spacing: Space.m) {
            CardHeader(
              plus.parcels.count == 1
                ? "A parcel is here" : "\(plus.parcels.count) parcels are here",
              detail: "Choose any one thing in the Shop. It's yours to keep.",
              symbol: "shippingbox.fill", tint: .honey, opens: false)
            PrimaryButton("Open the parcel") {
              model.send(ParcelMachine.Event.parcelTapped(first))
              choosing = true
            }
            .accessibilityIdentifier("openParcel")
          }
        }
      }
    }
  }

  private struct OfferView: View {
    let model: PlusModel
    let shelf: PlusMachine.Shelf
    let petName: String

    private var busy: Bool {
      switch model.state {
      case .buying, .restoring: true
      case .idle, .loading, .notOffered, .unavailable, .offered, .waiting, .delivering, .mine,
        .partners:
        false
      }
    }

    var body: some View {
      VStack(alignment: .leading, spacing: Space.section) {
        VStack(alignment: .leading, spacing: Space.s) {
          Text("A parcel every month, for the two of you.")
            .font(.ourioTitle)
            .foregroundStyle(Ink.text)
            .fixedSize(horizontal: false, vertical: true)
        }

        GroupedSection {
          Row(
            "Each month, choose any one thing in the Shop. It's yours to keep.",
            symbol: "shippingbox.fill", tint: .honey)
          Row("One of you pays. You both have it.", symbol: "heart.fill", tint: .blushPink)
          Row(
            "Nothing runs out. If you stop, everything you chose stays.",
            symbol: "infinity", tint: .sage)
        }

        if shelf.offers.isEmpty {
          Card {
            CardHeader(
              "The store didn't open", detail: "Nothing was charged. Try again later.",
              symbol: "wifi.exclamationmark", tint: Ink.textSecondary, opens: false)
          }
        } else {
          GroupedSection(inset: 0) {
            ForEach(shelf.offers) { offer in
              Button {
                model.send(PlusMachine.Event.planPicked(offer.plan))
              } label: {
                Row(planTitle(offer.plan)) {
                  HStack(spacing: Space.s) {
                    Text(planPrice(offer))
                      .font(.ourioCallout.monospacedDigit())
                      .foregroundStyle(Ink.textSecondary)
                    Image(systemName: offer.plan == shelf.plan ? "checkmark.circle.fill" : "circle")
                      .font(.ourioCallout)
                      .foregroundStyle(offer.plan == shelf.plan ? Ink.accentText : Ink.textTertiary)
                  }
                }
              }
              .buttonStyle(PressScaleStyle())
              .disabled(busy)
              .accessibilityAddTraits(offer.plan == shelf.plan ? .isSelected : [])
              .accessibilityIdentifier("plan-\(offer.plan.rawValue)")
            }
          }

          VStack(alignment: .leading, spacing: Space.s) {
            if let offer = shelf.selected {
              Button {
                model.send(PlusMachine.Event.buyTapped)
              } label: {
                if case .buying = model.state {
                  ProgressView().tint(Ink.heroInk)
                } else {
                  Text("Start for \(planPrice(offer))")
                }
              }
              .buttonStyle(PrimaryButtonStyle())
              .disabled(busy)
              .accessibilityIdentifier("subscribe")
              Text(renewal(offer.plan))
                .font(.ourioCaption)
                .foregroundStyle(Ink.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let status {
              Text(status)
                .font(.ourioCallout)
                .foregroundStyle(Ink.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("plusStatus")
            }
          }
        }

        HStack(spacing: Space.m) {
          Button("Restore purchase") { model.send(PlusMachine.Event.restoreTapped) }
            .disabled(busy)
            .accessibilityIdentifier("restorePlus")
          Link("Terms", destination: PlusLinks.terms)
          Link("Privacy", destination: PlusLinks.privacy)
        }
        .font(.ourioCaption)
        .foregroundStyle(Ink.accentText)
      }
    }

    private func planTitle(_ plan: PlusCatalog.Plan) -> String {
      switch plan {
      case .monthly: "Monthly"
      case .yearly: "Yearly"
      }
    }

    private func planPrice(_ offer: PlusOffer) -> String {
      switch offer.plan {
      case .monthly: "\(offer.displayPrice) a month"
      case .yearly: "\(offer.displayPrice) a year"
      }
    }

    private func renewal(_ plan: PlusCatalog.Plan) -> String {
      let period =
        switch plan {
        case .monthly: "month"
        case .yearly: "year"
        }
      return "Renews each \(period) until you cancel. Cancel any time in Settings > your name > "
        + "Subscriptions; what you chose stays."
    }

    private var status: String? {
      switch model.state {
      case .waiting: "Waiting for a parent to say yes. Nothing to do here."
      case .delivering: "Paid. Plus starts as soon as Ourio reaches its server."
      case .offered(let shelf):
        shelf.failure.map(Self.message)
      case .idle, .loading, .notOffered, .unavailable, .buying, .restoring, .mine, .partners: nil
      }
    }

    static func message(_ error: PaymentsError) -> String {
      switch error {
      case .subscriptionTaken:
        "This subscription belongs to another Ourio account on this Apple Account."
      case .notAllowed: "Purchases are turned off on this iPhone."
      case .unavailable: "Couldn't reach the store. Nothing was charged; try again."
      case .rejected, .failed, .unknownProduct: "That didn't go through. Nothing was charged."
      }
    }
  }

  private struct HasPlus: View {
    let plus: PlusResponse
    let mine: Bool
    let petName: String

    var body: some View {
      VStack(alignment: .leading, spacing: Space.section) {
        Text(headline)
          .font(.ourioTitle)
          .foregroundStyle(Ink.text)
          .fixedSize(horizontal: false, vertical: true)

        GroupedSection(footer: footer, inset: 0) {
          Row("Parcels so far") { value("\(plus.opened + plus.parcels.count)") }
          Row("Waiting to be opened") { value("\(plus.parcels.count)") }
          if let next = plus.nextParcel.flatMap(Self.day) {
            Row("Next parcel") { value(next) }
          }
          if let plan {
            Row(plan)
          }
        }

        if mine {
          GroupedSection(inset: 0) {
            Link(destination: PlusLinks.manage) {
              Row("Manage subscription") { RowChevron() }
            }
            Link(destination: PlusLinks.refund) {
              Row("Request a refund") { RowChevron() }
            }
          }
        }
      }
    }

    private var headline: String {
      switch plus.state {
      case .grace: "Apple couldn't take the payment. Check it in Settings; parcels keep coming."
      case .ending(_, let until):
        "Plus runs until \(Self.day(until) ?? until). Everything you chose stays."
      case .active, .none, .ended: "You set this up for the two of you. \(petName) says thanks."
      case .shared: "Your partner set this up for the two of you."
      }
    }

    private var plan: String? {
      switch plus.state {
      case .active(let plan, _), .ending(let plan, _), .grace(let plan):
        switch plan {
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
      case .none, .shared, .ended: nil
      }
    }

    private var footer: String? {
      if plus.bothPay {
        return
          "You both have Plus, so two parcels come each month. One is enough: either of you can cancel."
      }
      return mine
        ? "Cancelling keeps everything you both chose."
        : "Your partner looks after the subscription."
    }

    private func value(_ text: String) -> some View {
      Text(text).font(.ourioCallout.monospacedDigit()).foregroundStyle(Ink.textSecondary)
    }

    static func day(_ iso: String) -> String? {
      let parser = ISO8601DateFormatter()
      parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      guard let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
        return nil
      }
      return date.formatted(.dateTime.day().month(.abbreviated))
    }
  }

  /// One parcel's choice: any piece the pair hasn't got, up to the ceiling's price.
  struct ParcelChooser: View {
    let model: PlusModel
    let shop: ShopModel
    let petName: String
    @Environment(\.dismiss) private var dismiss

    private var items: [ShopItem] {
      ParcelChoices.items(owned: shop.owned, cat: petName)
    }

    var body: some View {
      BilletSheet("Choose one thing", subtitle: "It's a gift: no coins needed.", size: .large) {
        VStack(alignment: .leading, spacing: Space.section) {
          switch model.parcel {
          case .opened(let offer):
            EmptyState(
              symbol: "gift.fill", title: "It's yours",
              text: "\(name(of: offer)) is in your room's closet, for the two of you.")
            PrimaryButton("Done") {
              model.send(ParcelMachine.Event.closeTapped)
              dismiss()
            }
          case .closed, .choosing, .picked, .opening, .failed:
            ItemGrid {
              ForEach(items) { item in
                ItemCard(
                  item.name, subtitle: nil, opens: "Chooses \(item.name)",
                  open: { model.send(ParcelMachine.Event.offerPicked(.item(RoomItemId(item.id)))) }
                ) {
                  art(item)
                } footer: {
                  if picked == .item(RoomItemId(item.id)) {
                    Chip("Chosen", symbol: "checkmark", style: .honey)
                  }
                }
              }
            }
            if let failure { Text(failure).font(.ourioCallout).foregroundStyle(Ink.textSecondary) }
            if let picked {
              Button {
                model.send(ParcelMachine.Event.confirmTapped)
              } label: {
                if case .opening = model.parcel {
                  ProgressView().tint(Ink.heroInk)
                } else {
                  Text("Choose \(name(of: picked))")
                }
              }
              .buttonStyle(PrimaryButtonStyle())
              .disabled(model.parcel.isOpening)
              .accessibilityIdentifier("confirmParcel")
            }
            SecondaryButton("Not now") {
              model.send(ParcelMachine.Event.closeTapped)
              dismiss()
            }
            .disabled(model.parcel.isOpening)
          }
        }
      }
      .interactiveDismissDisabled(model.parcel.isOpening)
    }

    private var picked: ParcelOffer? {
      switch model.parcel {
      case .picked(_, let offer), .opening(_, let offer), .failed(_, let offer, _): offer
      case .closed, .choosing, .opened: nil
      }
    }

    private var failure: String? {
      guard case .failed(_, _, let error) = model.parcel else { return nil }
      return switch error {
      case .owned: "You have that one already. Choose something else."
      case .refused: "That one can't come in a parcel. Choose something else."
      case .gone: "This parcel was opened already."
      case .unavailable: "Couldn't reach Ourio. The parcel waits; try again."
      }
    }

    private func name(of offer: ParcelOffer) -> String {
      switch offer {
      case .item(let id): Catalog.item(id.rawValue, cat: petName)?.name ?? "It"
      case .ink(let id): shop.inks.first { $0.id == id.rawValue }?.name ?? "The ink"
      case .postage: "The stamp"
      }
    }

    private func art(_ item: ShopItem) -> some View {
      Group {
        if let image = Thumbnails.image(item.thumbnail, maxPixels: 512) {
          Image(uiImage: image).resizable().scaledToFit().padding(Space.s)
        } else {
          Image(systemName: "cube.box")
            .ourioScaledFont(size: 34, relativeTo: .largeTitle)
            .foregroundStyle(Ink.textTertiary)
        }
      }
    }
  }

  extension ParcelMachine.State {
    var isOpening: Bool {
      if case .opening = self { true } else { false }
    }
  }
#endif
