#if canImport(UIKit)
  import Design
  import Payments
  import SwiftUI
  import UsInterface
  import ShopInterface
  import WidgetBridge
  import Wire

  /// The one place that sells coins; Home itself never does.
  public struct CoinsSheet: View {
    let state: any ShopHost
    /// Nil in a build without a server: then nothing is sold.
    let packs: CoinPacksModel?
    var ask: CoinsAsk

    public init(
      state: any ShopHost, packs: CoinPacksModel?, ask: CoinsAsk = CoinsAsk(missing: 0, retry: nil)
    ) {
      self.state = state
      self.packs = packs
      self.ask = ask
    }
    @Environment(\.dismiss) private var dismiss

    private var sellsPacks: Bool {
      packs != nil && CoinPacksModel.sells(state.remoteFlags)
    }

    public var body: some View {
      BilletSheet("Coins", size: .large) {
        VStack(alignment: .leading, spacing: Space.section) {
          balance
          if let debt {
            DebtCard(debt: debt)
          }
          if let retry = ask.retry {
            ShortBanner(state: state, retry: retry, canBuy: sellsPacks) { dismiss() }
          }
          if let packs, sellsPacks {
            PackStore(model: packs, fit: CoinPacksModel.fit(for: missing, in: packs.packs))
            PlusHero(mockStore: state.storeIsMock, avatar: state.coatAvatarName)
          } else {
            EarnedOnly()
          }
          waysCard
          recent
        }
      }
      .accessibilityIdentifier("coinsSheet")
      .task { await state.shop.loadHistory() }
      .task { if sellsPacks { await packs?.load() } }
    }

    private var missing: Int { ask.retry.map { state.shop.shortBy($0.cost) } ?? 0 }

    private var debt: CoinDebt? {
      CoinDebt(balance: state.shop.balance, history: state.shop.history)
    }

    private var balance: some View {
      Card(warm: true) {
        HStack(spacing: Space.l) {
          CoinIcon(size: 56)
          VStack(alignment: .leading, spacing: 2) {
            Text(state.shop.debt > 0 ? "−\(state.shop.debt)" : "\(state.shop.coins)")
              .font(.ourioLargeTitleDigits)
              .foregroundStyle(Ink.text)
              .contentTransition(.numericText())
              .animation(.snappy, value: state.shop.balance)
            Text(debt?.caption ?? "coins for the two of you")
              .font(.ourioCallout)
              .foregroundStyle(Ink.textSecondary)
          }
          Spacer(minLength: 0)
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("coinBalance")
    }

    // MARK: Earning

    private var waysCard: some View {
      GroupedSection(header: "How to earn") {
        ForEach(ways, id: \.text) { way in
          Row(way.text, symbol: way.symbol, tint: way.tint.color)
        }
      }
    }

    private var ways: [(symbol: String, tint: UsTint, text: String)] {
      [
        ("note.text", .sun, "Send each other notes and photos"),
        ("heart.fill", .blush, "Look after \(state.petName) and play together"),
        ("gift.fill", .coral, "Open the daily gift"),
        ("checklist", .sage, "Tick off things you want to do"),
        ("sparkles", .lilac, "Match on a date idea, then rate the date"),
        ("shippingbox.fill", .sky, "Mark a wished-for gift as received"),
        ("square.grid.2x2.fill", .honey, "Complete a collection"),
      ]
    }

    @ViewBuilder private var recent: some View {
      if !state.shop.history.isEmpty {
        GroupedSection(header: "Recently") {
          ForEach(state.shop.history, id: \.id) { entry in
            HistoryRow(line: CoinLine(entry, offers: state.shop.offers))
          }
        }
        .accessibilityIdentifier("coinHistory")
      }
    }
  }

  private struct DebtCard: View {
    let debt: CoinDebt

    var body: some View {
      Card {
        CardHeader(debt.title, detail: debt.detail, symbol: "arrow.uturn.backward", opens: false)
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("coinDebt")
    }
  }

  private struct HistoryRow: View {
    let line: CoinLine

    var body: some View {
      Row(
        line.title, detail: line.date.formatted(.relative(presentation: .named)),
        symbol: line.symbol, tint: line.isGain ? UsTint.honey.color : UsTint.sky.color
      ) {
        Text(line.amount)
          .font(.ourioHeadline.monospacedDigit())
          .foregroundStyle(line.isGain ? Ink.accentText : Ink.textSecondary)
      }
      .accessibilityElement(children: .combine)
    }
  }

  /// Where packs would be in a build that sells none: coins are earned, and that is how it is meant to be.
  private struct EarnedOnly: View {
    var body: some View {
      Card {
        CardHeader(
          "Every coin is earned",
          detail: "Nothing is for sale. Coins come from what you two do together.",
          symbol: "sparkles", opens: false)
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("coinsEarnedOnly")
    }
  }

  private struct ShortBanner: View {
    let state: any ShopHost
    let retry: CoinsAsk.Retry
    let canBuy: Bool
    let done: () -> Void

    private var missing: Int { state.shop.shortBy(retry.cost) }

    var body: some View {
      Card {
        VStack(alignment: .leading, spacing: Space.s) {
          if missing > 0 {
            CardHeader("You need \(missing) more") {
              CoinIcon(size: Size.cardMark * 0.8)
            } detail: {
              Text(
                canBuy
                  ? "for \(retry.title), \(retry.cost) coins."
                  : "for \(retry.title), \(retry.cost) coins. Earn them together, the ways are below."
              )
            } trailing: {
              EmptyView()
            }
            .monospacedDigit()
            .contentTransition(.numericText())
          } else {
            Text("You have enough now")
              .font(.ourioHeadline)
              .foregroundStyle(Ink.text)
            Button {
              if state.shop.finish(retry) { done() }
            } label: {
              HStack(spacing: Space.s) {
                Text("Buy \(retry.title) for")
                CoinIcon(size: 18)
                Text(retry.cost, format: .number).monospacedDigit()
              }
              .lineLimit(1)
              .minimumScaleFactor(0.8)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("finishBuy")
          }
        }
      }
      .animation(.snappy, value: missing)
      .accessibilityIdentifier("shortBanner")
    }
  }
#endif
