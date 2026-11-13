import { describe, expect, it } from "vitest";
import { type CatEvent } from "@billet/contracts-domain/cat";
import { CoinEntryId } from "@billet/contracts-domain/coins";
import { treatPrice } from "@billet/contracts-domain/shop";
import type { EpochMillis } from "@billet/contracts-domain/ids";
import { Schema } from "effect";
import { decide } from "../src/decide.ts";
import { RoomCommand } from "../src/room-command.ts";
import type { RoomDecision } from "../src/room-decision.ts";
import type { ActiveRoom } from "../src/room-state.ts";
import { alice, rose, uuid, withCat } from "./samples.ts";

const start: EpochMillis = 1_700_000_000_000;
const entryId = Schema.decodeSync(CoinEntryId);

const accept = (room: ActiveRoom, command: RoomCommand): RoomDecision & { _tag: "Accepted" } => {
  const decision = decide(room, command);
  if (decision._tag !== "Accepted") throw new Error(`rejected: ${decision.rejection._tag}`);
  return decision;
};

const refund = (coins: number, id = "refund:2000") =>
  RoomCommand.cases.CreditPurchase.make({
    id: entryId(id),
    kind: "refund",
    coins,
    ref: "com.ourio.app.coins.550",
    at: start,
  });

const buyInk = (n: number) =>
  RoomCommand.cases.Buy.make({ id: uuid(n), by: alice, ink: rose, at: start });

const pet = (n: number, event: CatEvent = { _tag: "Petted" }) =>
  RoomCommand.cases.RecordCatEvent.make({ id: uuid(n), by: alice, at: start, event });

const withBalance = (balance: number): ActiveRoom => ({
  ...withCat,
  wallet: { ...withCat.wallet, balance },
});

describe("a refund that leaves the pair in debt", () => {
  const indebted = accept(withBalance(10), refund(550)).state;

  it("is the signed balance, with no second tracker", () => {
    expect(indebted.wallet.balance).toBe(-540);
  });

  it.each([
    ["an ink", buyInk(1), 60],
    [
      "a treat",
      RoomCommand.cases.Order.make({ id: uuid(2), by: alice, at: start, offer: { _tag: "Treat" } }),
      treatPrice,
    ],
  ])(
    "refuses %s while the balance is negative, naming what is needed and held",
    (_, command, needed) => {
      expect(decide(indebted, command)).toEqual({
        _tag: "Rejected",
        rejection: { _tag: "NotEnoughCoins", needed, have: -540 },
      });
    },
  );

  it("spends only from a balance of at least the price", () => {
    expect(decide(withBalance(59), buyInk(1))).toMatchObject({ _tag: "Rejected" });
    expect(decide(withBalance(60), buyInk(1))).toMatchObject({ _tag: "Accepted" });
  });

  it("still earns, and the earnings pay the debt down before anything is spendable", () => {
    const paid = accept(indebted, pet(3));
    expect(paid.outputs).toMatchObject([
      { _tag: "CatEntryAppended" },
      { _tag: "CoinsEntered", entry: { kind: "earn", amount: 1 } },
    ]);
    expect(paid.state.wallet.balance).toBe(-539);
  });

  it("takes nothing else back: the entries and daily counts already earned stay", () => {
    const earned = accept(withBalance(0), pet(4)).state;
    const refunded = accept(earned, refund(550)).state;
    expect(refunded.wallet).toEqual({ ...earned.wallet, balance: earned.wallet.balance - 550 });
  });

  it("is spendable again once earning covers the price", () => {
    const nearly = accept(withBalance(-1), refund(0, "refund:2001")).state;
    expect(decide(nearly, buyInk(5))).toMatchObject({ _tag: "Rejected" });
    expect(
      decide({ ...nearly, wallet: { ...nearly.wallet, balance: 60 } }, buyInk(5)),
    ).toMatchObject({
      _tag: "Accepted",
    });
  });
});
