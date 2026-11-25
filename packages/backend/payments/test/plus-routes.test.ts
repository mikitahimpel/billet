import { Clock, Effect, Layer, Option, Redacted, Schema } from "effect";
import { SecureRandom, Signature } from "effect/crypto";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthService } from "@billet/backend-auth/auth-service";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { DeviceId, UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { OpenParcelResponse, PlusResponse } from "@billet/contracts-http-api/plus";
import { PaymentsConfig, settingsForStage } from "../src/payments-config.ts";
import { PaymentsRepository } from "../src/payments-repository.ts";
import { PaymentsRoutes } from "../src/payments-routes.ts";
import { PaymentsService } from "../src/payments-service.ts";
import { PaymentsSwitch } from "../src/payments-switch.ts";
import { PairWallet } from "../src/pair-wallet.ts";
import { PlusGate } from "../src/plus-gate.ts";
import { PlusRepository } from "../src/plus-repository.ts";
import { PlusRoutes } from "../src/plus-routes.ts";
import { PlusService } from "../src/plus-service.ts";
import { addMonths } from "../src/plus-rules.ts";
import { makeChain, notificationPayload, signJws, transactionPayload } from "./app-store-signer.ts";
import { makeInMemoryPairWallet } from "./in-memory-pair-wallet.ts";
import { makeInMemoryPaymentsRepository } from "./in-memory-payments-repository.ts";
import { makeInMemoryPlusRepository } from "./in-memory-plus-repository.ts";

const decodeUser = Schema.decodeSync(UserId);
const decodePair = Schema.decodeSync(PairId);

// `leo` and `mia` are a pair, `ana` and `teen` another (`teen` said 13 to 17), `solo` has none.
const pairs: Record<string, string> = {
  leo: "pair-a",
  mia: "pair-a",
  ana: "pair-b",
  teen: "pair-b",
};
const membersOf = (pairId: string) =>
  Object.entries(pairs)
    .filter(([, pair]) => pair === pairId)
    .map(([user]) => decodeUser(user));

const FakeAuth = Layer.succeed(
  AuthService,
  AuthService.of({
    issueChallenge: Effect.die("unused"),
    signInAnonymously: () => Effect.die("unused"),
    signInWithApple: () => Effect.die("unused"),
    linkApple: () => Effect.die("unused"),
    account: () => Effect.die("unused"),
    signOut: () => Effect.die("unused"),
    registerPushToken: () => Effect.die("unused"),
    authenticate: (token) => {
      const raw = Redacted.value(token);
      return Effect.succeed({
        userId: decodeUser(raw),
        deviceId: Schema.decodeSync(DeviceId)(`device-${raw}`),
        sessionHash: `hash-${raw}`,
      });
    },
  }),
);

const FakePairing = Layer.succeed(PairingRepository, {
  saveInvite: () => Effect.die("unused"),
  claimInvite: () => Effect.die("unused"),
  pairedAt: () => Effect.die("unused"),
  unpair: () => Effect.die("unused"),
  block: () => Effect.die("unused"),
  keep: () => Effect.die("unused"),
  kept: () => Effect.die("unused"),
  clearKept: () => Effect.die("unused"),
  saveReport: () => Effect.die("unused"),
  findMembers: (pairId) => Effect.succeed(membersOf(pairId)),
  findPair: (userId) => {
    const pair = pairs[userId];
    return Effect.succeed(pair === undefined ? Option.none() : Option.some(decodePair(pair)));
  },
});

const MinorGate = Layer.succeed(PlusGate, {
  closedFor: (userId) => Effect.succeed(userId === "teen" ? "declared-minor" : undefined),
});

const now = Date.UTC(2026, 10, 20, 12);
const fixedClock: Clock.Clock = {
  currentTimeMillis: Effect.succeed(now),
  currentTimeMillisUnsafe: () => now,
  currentTimeNanos: Effect.succeed(BigInt(now) * 1_000_000n),
  currentTimeNanosUnsafe: () => BigInt(now) * 1_000_000n,
  monotonicTimeNanos: Effect.succeed(BigInt(now) * 1_000_000n),
  monotonicTimeNanosUnsafe: () => BigInt(now) * 1_000_000n,
  sleep: () => Effect.void,
};

const apple = await makeChain();
const cryptoLayer = Signature.layerWebCrypto.pipe(Layer.provide(SecureRandom.layerWebCrypto));

const setup = (stage: string, gate: Layer.Layer<PlusGate> = MinorGate) => {
  const rooms = makeInMemoryPairWallet();
  const config = PaymentsConfig.with(settingsForStage(stage, [apple.root]));
  const app = HttpRouter.toWebHandler(
    Layer.mergeAll(PaymentsRoutes, PlusRoutes).pipe(
      Layer.provide(
        Layer.mergeAll(
          FakeAuth,
          PaymentsService.layer.pipe(Layer.provideMerge(PlusService.layer)),
          PaymentsSwitch.on,
          gate,
          config,
        ),
      ),
      Layer.provide(
        Layer.mergeAll(
          Layer.succeed(PaymentsRepository, makeInMemoryPaymentsRepository().repository),
          Layer.succeed(PlusRepository, makeInMemoryPlusRepository()),
          Layer.succeed(PairWallet, rooms.wallet),
          FakePairing,
          config,
          cryptoLayer,
        ),
      ),
    ),
    {
      disableLogger: true,
      middleware: (effect) => Effect.provideService(effect, Clock.Clock, fixedClock),
    },
  );
  return { ...app, rooms };
};

const bearer = (user: string) => ({ authorization: `Bearer ${user}` });

const request = (method: string, path: string, user: string, body?: unknown) =>
  new Request(`http://billet.test${path}`, {
    method,
    headers: { "content-type": "application/json", ...bearer(user) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });

const decodePlus = Schema.decodeUnknownSync(PlusResponse);
const decodeOpened = Schema.decodeUnknownSync(OpenParcelResponse);

const day = 86_400_000;
let sequence = 0;
const nextId = () => {
  sequence += 1;
  return `30000009${String(sequence).padStart(8, "0")}`;
};

const monthly = "com.ourio.app.plus.monthly";
const yearly = "com.ourio.app.plus.yearly";

/** An Apple-signed subscription transaction, bought `ago` milliseconds before now. */
const subscription = (
  overrides: { productId?: string; ago?: number; otid?: string; [key: string]: unknown } = {},
) => {
  const { ago = 0, otid, productId = monthly, ...rest } = overrides;
  const id = nextId();
  const purchaseDate = now - ago;
  return {
    id,
    otid: otid ?? id,
    jws: signJws(
      transactionPayload({
        transactionId: id,
        originalTransactionId: otid ?? id,
        productId,
        type: "Auto-Renewable Subscription",
        purchaseDate,
        expiresDate: addMonths(purchaseDate, productId === yearly ? 12 : 1),
        signedDate: now,
        ...rest,
      }),
      apple.chain,
      apple.leafKey,
    ),
  };
};

const renewalInfo = (otid: string, fields: Record<string, unknown>) =>
  signJws({ originalTransactionId: otid, signedDate: now, ...fields }, apple.chain, apple.leafKey);

const notification = async (
  type: string,
  signedTransactionInfo: string,
  extra: { subtype?: string; signedRenewalInfo?: string } = {},
) => {
  const payload = notificationPayload(
    type,
    signedTransactionInfo,
    extra.subtype === undefined ? {} : { subtype: extra.subtype },
  );
  const data =
    extra.signedRenewalInfo === undefined
      ? payload.data
      : { ...payload.data, signedRenewalInfo: extra.signedRenewalInfo };
  return {
    signedPayload: await signJws({ ...payload, data }, apple.chain, apple.leafKey),
  };
};

describe("Ourio Plus", () => {
  const app = setup("prod");
  afterAll(() => app.dispose());
  const { handler, rooms } = app;

  const view = async (user: string) => {
    const response = await handler(request("GET", "/v1/plus", user));
    expect(response.status).toBe(200);
    return decodePlus(await response.json());
  };
  const subscribe = async (user: string, signedTransaction: string, signedRenewalInfo?: string) =>
    handler(
      request("POST", "/v1/plus/subscribe", user, {
        signedTransaction,
        ...(signedRenewalInfo === undefined ? {} : { signedRenewalInfo }),
      }),
    );
  const open = (user: string, parcel: string, offer: unknown) =>
    handler(request("POST", "/v1/plus/parcels/open", user, { parcel, offer }));
  const notify = async (body: unknown) =>
    handler(
      new Request("http://billet.test/v1/appstore/notifications", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
      }),
    );
  const yarn = { _tag: "Item", item: "yarn" };

  it("is None for a pair that never had it, and every choice is left", async () => {
    const plus = await view("ana");
    expect(plus.state).toEqual({ _tag: "None" });
    expect(plus.parcels).toEqual([]);
    expect(plus.choicesLeft).toBeGreaterThan(20);
  });

  it("gives both partners Plus when one pays, with one parcel at once", async () => {
    const bought = subscription();
    const response = await subscribe("leo", await bought.jws);
    expect(response.status).toBe(200);
    const payer = decodePlus(await response.json());
    expect(payer.state._tag).toBe("Active");
    expect(payer.parcels.map(({ id }) => id)).toEqual([`parcel:${bought.id}`]);
    const partner = await view("mia");
    expect(partner.state).toEqual({ _tag: "Shared" });
    expect(partner.parcels).toEqual(payer.parcels);
  });

  it("binds a subscription once: the same account again changes nothing, another is refused", async () => {
    const bought = subscription();
    const jws = await bought.jws;
    expect((await subscribe("ana", jws)).status).toBe(200);
    expect((await subscribe("ana", jws)).status).toBe(200);
    expect((await view("ana")).parcels).toHaveLength(1);
    const taken = await subscribe("leo", jws);
    expect(taken.status).toBe(409);
    expect(await taken.json()).toEqual({ _tag: "SubscriptionTaken" });
  });

  it("refuses a coin pack, a revoked or family-shared transaction, and a foreign renewal", async () => {
    const pack = signJws(
      transactionPayload({ transactionId: nextId() }),
      apple.chain,
      apple.leafKey,
    );
    expect((await subscribe("ana", await pack)).status).toBe(400);
    const revoked = subscription({ revocationDate: now });
    expect((await subscribe("ana", await revoked.jws)).status).toBe(400);
    const shared = subscription({ inAppOwnershipType: "FAMILY_SHARED" });
    expect((await subscribe("ana", await shared.jws)).status).toBe(400);
    const bought = subscription();
    const other = await renewalInfo("someone-else", { autoRenewStatus: 1 });
    expect((await subscribe("ana", await bought.jws, other)).status).toBe(400);
  });

  it("takes renewal and grace from the phone's renewal info", async () => {
    const bought = subscription({ ago: 40 * day });
    const off = await renewalInfo(bought.otid, { autoRenewStatus: 0 });
    // The period is over: the expiry is in the past and Apple is retrying.
    const grace = await renewalInfo(bought.otid, {
      autoRenewStatus: 1,
      gracePeriodExpiresDate: now + 5 * day,
    });
    const fresh = setup("prod");
    expect(
      (
        await fresh.handler(
          request("POST", "/v1/plus/subscribe", "leo", {
            signedTransaction: await bought.jws,
            signedRenewalInfo: grace,
          }),
        )
      ).status,
    ).toBe(200);
    const graced = decodePlus(
      await (await fresh.handler(request("GET", "/v1/plus", "leo"))).json(),
    );
    expect(graced.state).toEqual({ _tag: "Grace", plan: "monthly" });
    const partner = decodePlus(
      await (await fresh.handler(request("GET", "/v1/plus", "mia"))).json(),
    );
    expect(partner.state).toEqual({ _tag: "Shared" });
    const current = subscription({ otid: bought.otid });
    await fresh.handler(
      request("POST", "/v1/plus/subscribe", "leo", {
        signedTransaction: await current.jws,
        signedRenewalInfo: off,
      }),
    );
    const ending = decodePlus(
      await (await fresh.handler(request("GET", "/v1/plus", "leo"))).json(),
    );
    expect(ending.state._tag).toBe("Ending");
    expect(ending.parcels).toHaveLength(2);
    await fresh.dispose();
  });

  it("opens a parcel as one piece for no coins, once", async () => {
    const parcel = (await view("leo")).parcels[0]?.id ?? "";
    const response = await open("mia", parcel, yarn);
    expect(response.status).toBe(200);
    const opened = decodeOpened(await response.json());
    expect(opened.shop.items).toContain("yarn");
    expect(opened.shop.balance).toBe(0);
    expect(opened.plus.parcels).toEqual([]);
    expect(opened.plus.opened).toBe(1);
    // The same open again answers the same; another choice for it is refused.
    expect((await open("leo", parcel, yarn)).status).toBe(200);
    const again = await open("leo", parcel, { _tag: "Item", item: "rug" });
    expect(again.status).toBe(409);
    expect(await again.json()).toEqual({ _tag: "ParcelOpened" });
    expect(rooms.balance("pair-a")).toBe(0);
  });

  it("refuses the dearest pieces, unsold ones, owned ones and parcels the pair has not got", async () => {
    const bought = subscription();
    await subscribe("leo", await bought.jws);
    const parcel = `parcel:${bought.id}`;
    expect((await open("leo", parcel, { _tag: "Item", item: "tower" })).status).toBe(400);
    expect((await open("leo", parcel, { _tag: "Item", item: "donutbed" })).status).toBe(400);
    expect((await open("leo", parcel, { _tag: "Item", item: "lamp" })).status).toBe(400);
    expect((await open("leo", parcel, { _tag: "Ink", ink: "ink-graphite" })).status).toBe(400);
    const owned = await open("leo", parcel, yarn);
    expect(owned.status).toBe(409);
    expect(await owned.json()).toEqual({ _tag: "AlreadyOwned", itemId: "yarn" });
    expect((await open("ana", parcel, { _tag: "Ink", ink: "ink-rose" })).status).toBe(404);
    expect((await open("leo", "parcel:nothing", { _tag: "Ink", ink: "ink-rose" })).status).toBe(
      404,
    );
    expect((await open("leo", parcel, { _tag: "Item", item: "armchair" })).status).toBe(200);
  });

  it("brings a parcel for each renewal, once however often Apple says so", async () => {
    const first = subscription();
    await subscribe("ana", await first.jws);
    const renewed = subscription({ otid: first.otid });
    const body = await notification("DID_RENEW", await renewed.jws);
    expect((await notify(body)).status).toBe(200);
    expect((await notify(body)).status).toBe(200);
    const again = await notification("DID_RENEW", await renewed.jws);
    expect((await notify(again)).status).toBe(200);
    const ids = (await view("ana")).parcels.map(({ id }) => id);
    expect(ids).toContain(`parcel:${first.id}`);
    expect(ids).toContain(`parcel:${renewed.id}`);
    expect(ids.filter((id) => id === `parcel:${renewed.id}`)).toHaveLength(1);
  });

  it("follows a cancel and a failed payment, and keeps the parcels when it ends", async () => {
    const fresh = setup("prod");
    const get = async (user: string) =>
      decodePlus(await (await fresh.handler(request("GET", "/v1/plus", user))).json());
    const post = async (body: unknown) =>
      fresh.handler(
        new Request("http://billet.test/v1/appstore/notifications", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(body),
        }),
      );
    const bought = subscription();
    const jws = await bought.jws;
    await fresh.handler(request("POST", "/v1/plus/subscribe", "mia", { signedTransaction: jws }));
    await post(
      await notification("DID_CHANGE_RENEWAL_STATUS", jws, { subtype: "AUTO_RENEW_DISABLED" }),
    );
    expect((await get("mia")).state._tag).toBe("Ending");
    expect((await get("leo")).state).toEqual({ _tag: "Shared" });
    await post(
      await notification("DID_CHANGE_RENEWAL_STATUS", jws, { subtype: "AUTO_RENEW_ENABLED" }),
    );
    expect((await get("mia")).state._tag).toBe("Active");
    const lapsed = subscription({ otid: bought.otid, ago: 40 * day });
    await post(
      await notification("DID_FAIL_TO_RENEW", await lapsed.jws, {
        subtype: "GRACE_PERIOD",
        signedRenewalInfo: await renewalInfo(bought.otid, {
          autoRenewStatus: 1,
          gracePeriodExpiresDate: now + 3 * day,
        }),
      }),
    );
    // The first transaction's expiry still lies ahead, so it is still active.
    expect((await get("mia")).state._tag).toBe("Active");
    await post(await notification("EXPIRED", jws, { subtype: "VOLUNTARY" }));
    const ended = await get("mia");
    expect(["Ending", "Ended"]).toContain(ended.state._tag);
    expect(ended.parcels.length).toBeGreaterThanOrEqual(1);
    await fresh.dispose();
  });

  it("takes back a refunded month: a waiting parcel goes, an opened one is owed in coins", async () => {
    const fresh = setup("prod");
    const post = async (body: unknown) =>
      fresh.handler(
        new Request("http://billet.test/v1/appstore/notifications", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(body),
        }),
      );
    const first = subscription();
    await fresh.handler(
      request("POST", "/v1/plus/subscribe", "leo", { signedTransaction: await first.jws }),
    );
    const second = subscription({ otid: first.otid });
    await post(await notification("DID_RENEW", await second.jws));
    const opened = await fresh.handler(
      request("POST", "/v1/plus/parcels/open", "leo", {
        parcel: `parcel:${first.id}`,
        offer: { _tag: "Item", item: "monstera" },
      }),
    );
    expect(opened.status).toBe(200);

    const refund = await notification("REFUND", await first.jws);
    expect((await post(refund)).status).toBe(200);
    expect((await post(refund)).status).toBe(200);
    await post(await notification("REFUND", await second.jws));
    expect(fresh.rooms.entries("pair-a")).toEqual([[`refund:parcel:${first.id}`, -90]]);
    expect(fresh.rooms.owned("pair-a")).toContain("Item:monstera");
    const plus = decodePlus(await (await fresh.handler(request("GET", "/v1/plus", "leo"))).json());
    expect(plus.parcels).toEqual([]);

    await post(await notification("REFUND_REVERSED", await first.jws));
    expect(fresh.rooms.balance("pair-a")).toBe(0);
    await fresh.dispose();
  });

  it("brings a year's parcels one a month", async () => {
    const bought = subscription({ productId: yearly, ago: 65 * day });
    const plus = decodePlus(await (await subscribe("mia", await bought.jws)).json());
    expect(
      plus.parcels.map(({ id }) => id).filter((id) => id.startsWith(`parcel:${bought.id}`)),
    ).toEqual([`parcel:${bought.id}:1`, `parcel:${bought.id}:2`, `parcel:${bought.id}:3`]);
    expect(plus.bothPay).toBe(true);
  });

  it("is a 404 for an account that said it is 13 to 17, and for one with no pair", async () => {
    const bought = subscription();
    for (const response of [
      await handler(request("GET", "/v1/plus", "teen")),
      await subscribe("teen", await bought.jws),
      await open("teen", `parcel:${bought.id}`, yarn),
      await handler(request("GET", "/v1/plus", "solo")),
    ]) {
      expect(response.status).toBe(404);
    }
    // Nothing was bound to the minor, so their partner was given nothing by it.
    expect((await view("ana")).parcels.map(({ id }) => id)).not.toContain(`parcel:${bought.id}`);
  });

  it("records a notification for a subscription no account has bound yet", async () => {
    const unbound = subscription();
    expect((await notify(await notification("SUBSCRIBED", await unbound.jws))).status).toBe(200);
  });

  it("has no mock route off the dev stage", async () => {
    const response = await handler(
      request("POST", "/v1/plus/mock", "leo", {
        plan: "monthly",
        transactionId: "mock-x",
        kind: "subscribe",
      }),
    );
    expect(response.status).toBe(404);
  });
});

describe("Ourio Plus behind its flag", () => {
  const app = setup("prod", PlusGate.closed("flag-off"));
  afterAll(() => app.dispose());

  it("answers 404 on every route", async () => {
    for (const [method, path] of [
      ["GET", "/v1/plus"],
      ["POST", "/v1/plus/subscribe"],
      ["POST", "/v1/plus/parcels/open"],
    ] as const) {
      const response = await app.handler(
        request(method, path, "leo", method === "GET" ? undefined : {}),
      );
      expect(response.status, path).toBe(404);
    }
  });
});

describe("Ourio Plus on the dev stage's mock App Store", () => {
  const app = setup("dev");
  afterAll(() => app.dispose());
  const mock = async (kind: string, transactionId = "mock-plus-1", plan = "monthly") => {
    const response = await app.handler(
      request("POST", "/v1/plus/mock", "leo", { plan, transactionId, kind }),
    );
    expect(response.status, kind).toBe(200);
    return decodePlus(await response.json());
  };

  it("subscribes, renews, cancels, fails, refunds and expires", async () => {
    expect((await mock("subscribe")).parcels).toHaveLength(1);
    expect((await mock("renew")).parcels).toHaveLength(2);
    expect((await mock("cancel")).state._tag).toBe("Ending");
    expect((await mock("fail")).state._tag).toBe("Grace");
    expect((await mock("refund")).parcels).toHaveLength(1);
    const ended = await mock("expire");
    expect(ended.state).toEqual({ _tag: "Ended" });
    expect(ended.parcels).toHaveLength(1);
  });

  it("refuses a mock of a subscription the caller does not have", async () => {
    const response = await app.handler(
      request("POST", "/v1/plus/mock", "mia", {
        plan: "monthly",
        transactionId: "mock-plus-1",
        kind: "renew",
      }),
    );
    expect(response.status).toBe(404);
  });
});
