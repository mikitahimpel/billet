import { Effect, Layer, Option, Redacted, Schema } from "effect";
import { SecureRandom, Signature } from "effect/crypto";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthRejected } from "@billet/backend-auth/auth-error";
import { AuthService } from "@billet/backend-auth/auth-service";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { DeviceId, UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { PurchaseResponse, PurchasesResponse } from "@billet/contracts-http-api/purchase";
import { PaymentsConfig, settingsForStage } from "../src/payments-config.ts";
import { PaymentsRepository, CoinOwner } from "../src/payments-repository.ts";
import { PaymentsRoutes } from "../src/payments-routes.ts";
import { PaymentsService } from "../src/payments-service.ts";
import { PaymentsSwitch } from "../src/payments-switch.ts";
import {
  makeChain,
  makeXcodeChain,
  notificationPayload,
  signJws,
  transactionPayload,
} from "./app-store-signer.ts";
import { makeInMemoryPaymentsRepository } from "./in-memory-payments-repository.ts";

// Callers are `<user>` bearer tokens; users whose name starts with `paired` are in the pair
// `pair-<user>`, everyone else has no partner.
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
      if (raw.startsWith("rejected")) return Effect.fail(new AuthRejected({ reason: "fake" }));
      return Effect.succeed({
        userId: Schema.decodeSync(UserId)(raw),
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
  findMembers: () => Effect.die("unused"),
  unpair: () => Effect.die("unused"),
  findPair: (userId) =>
    Effect.succeed(
      userId.startsWith("paired")
        ? Option.some(Schema.decodeSync(PairId)(`pair-${userId}`))
        : Option.none(),
    ),
});

const [apple, xcode] = await Promise.all([makeChain(), makeXcodeChain()]);

const cryptoLayer = Signature.layerWebCrypto.pipe(Layer.provide(SecureRandom.layerWebCrypto));

// Payments on unless a test says otherwise: these tests are about buying, not the flag.
const setup = (stage: string, payments: Layer.Layer<PaymentsSwitch> = PaymentsSwitch.on) => {
  const memory = makeInMemoryPaymentsRepository();
  const config = PaymentsConfig.with(settingsForStage(stage, [apple.root]));
  const app = HttpRouter.toWebHandler(
    PaymentsRoutes.pipe(
      Layer.provide(Layer.mergeAll(FakeAuth, PaymentsService.layer, payments, config)),
      Layer.provide(
        Layer.mergeAll(
          Layer.succeed(PaymentsRepository, memory.repository),
          FakePairing,
          config,
          cryptoLayer,
        ),
      ),
    ),
    { disableLogger: true },
  );
  return { ...app, memory };
};

const post = (path: string, body: unknown, headers: Record<string, string> = {}) =>
  new Request(`http://billet.test${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });

const bearer = (user: string) => ({ authorization: `Bearer ${user}` });

let sequence = 0;
/** A fresh Apple-signed transaction; `overrides` change its payload. */
const appleTransaction = (overrides: Record<string, unknown> = {}) => {
  sequence += 1;
  const id = `20000009${String(sequence).padStart(8, "0")}`;
  return signJws(
    transactionPayload({ transactionId: id, originalTransactionId: id, ...overrides }),
    apple.chain,
    apple.leafKey,
  );
};

const notification = async (type: string, signedTransactionInfo?: string, overrides = {}) => ({
  signedPayload: await signJws(
    notificationPayload(type, signedTransactionInfo, overrides),
    apple.chain,
    apple.leafKey,
  ),
});

const decodePurchase = Schema.decodeUnknownSync(PurchaseResponse);
const decodeCoins = Schema.decodeUnknownSync(PurchasesResponse);
const owner = Schema.decodeSync(CoinOwner);

describe("purchases on prod", () => {
  const app = setup("prod");
  afterAll(() => app.dispose());
  const { handler } = app;

  const buy = async (user: string, signedTransaction: string) =>
    handler(post("/v1/purchases", { signedTransaction }, bearer(user)));

  const purchasesOf = async (user: string) =>
    decodeCoins(
      await (
        await handler(new Request("http://billet.test/v1/purchases", { headers: bearer(user) }))
      ).json(),
    );

  it("credits a verified pack to the caller's pair, once", async () => {
    const signed = await appleTransaction({ productId: "com.mikitahimpel.billet.coins.550" });
    const first = await buy("paired-ana", signed);
    expect(first.status).toBe(200);
    const credited = decodePurchase(await first.json());
    expect(credited).toMatchObject({
      productId: "com.mikitahimpel.billet.coins.550",
      coins: 550,
      balance: 550,
      duplicate: false,
    });

    const again = decodePurchase(await (await buy("paired-ana", signed)).json());
    expect(again).toEqual({ ...credited, duplicate: true });

    const { balance, entries } = await purchasesOf("paired-ana");
    expect(balance).toBe(550);
    expect(entries).toEqual([
      {
        id: `purchase:${credited.transactionId}`,
        kind: "purchase",
        amount: 550,
        productId: "com.mikitahimpel.billet.coins.550",
        at: expect.stringMatching(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/),
      },
    ]);
  });

  it("accepts Production and Sandbox (TestFlight)", async () => {
    for (const environment of ["Production", "Sandbox"]) {
      const response = await buy("paired-env", await appleTransaction({ environment }));
      expect(response.status, environment).toBe(200);
    }
  });

  it.each([
    [
      "an Xcode transaction",
      () => signJws(transactionPayload({ environment: "Xcode" }), xcode.chain, xcode.leafKey),
    ],
    ["Apple naming the Xcode environment", () => appleTransaction({ environment: "Xcode" })],
    ["another app's bundle", () => appleTransaction({ bundleId: "com.example.other" })],
    [
      "a product that is not a pack",
      () => appleTransaction({ productId: "com.mikitahimpel.billet.coins.5" }),
    ],
    ["a non-consumable", () => appleTransaction({ type: "Non-Consumable" })],
    ["a revoked transaction", () => appleTransaction({ revocationDate: Date.UTC(2026, 10, 5) })],
    [
      "a chain to another root",
      async () => {
        const other = await makeChain();
        return signJws(transactionPayload(), other.chain, other.leafKey);
      },
    ],
    [
      "a bad signature",
      async () => {
        const [header, payload] = (await appleTransaction()).split(".");
        return `${header}.${payload}.${"A".repeat(86)}`;
      },
    ],
  ])("answers 400 InvalidPurchase for %s", async (_, make) => {
    const response = await buy("paired-bad", await make());
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ _tag: "InvalidPurchase" });
    expect((await purchasesOf("paired-bad")).balance).toBe(0);
  });

  it("answers 404 NotFound to a caller with no pair, and 401 without a session", async () => {
    const signed = await appleTransaction();
    const unpaired = await buy("solo", signed);
    expect(unpaired.status).toBe(404);
    expect(await unpaired.json()).toEqual({ _tag: "NotFound" });
    expect((await handler(post("/v1/purchases", { signedTransaction: signed }))).status).toBe(401);
    expect((await buy("rejected", signed)).status).toBe(401);
  });

  it("answers 400 InvalidRequest to a body without a transaction", async () => {
    const response = await handler(post("/v1/purchases", {}, bearer("paired-ana")));
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ _tag: "InvalidRequest" });
  });

  it("has no mock purchase route", async () => {
    const response = await handler(
      post(
        "/v1/purchases/mock",
        {
          productId: "com.mikitahimpel.billet.coins.100",
          transactionId: "mock-1",
          kind: "purchase",
        },
        bearer("paired-ana"),
      ),
    );
    expect(response.status).toBe(404);
  });

  it("ignores the demo room header", async () => {
    const signed = await appleTransaction();
    const response = await handler(
      post("/v1/purchases", { signedTransaction: signed }, { "x-billet-demo-room": "ABC123" }),
    );
    expect(response.status).toBe(401);
    const coins = await handler(
      new Request("http://billet.test/v1/purchases", {
        headers: { "x-billet-demo-room": "ABC123" },
      }),
    );
    expect(coins.status).toBe(401);
  });
});

describe("purchases on dev", () => {
  const app = setup("dev");
  afterAll(() => app.dispose());
  const { handler } = app;

  const buy = async (headers: Record<string, string>, signedTransaction: string) =>
    handler(post("/v1/purchases", { signedTransaction }, headers));

  it("accepts Sandbox and Xcode, and refuses Production", async () => {
    expect((await buy(bearer("paired-dev"), await appleTransaction())).status).toBe(200);
    const fromXcode = await signJws(
      transactionPayload({ environment: "Xcode", transactionId: "0", originalTransactionId: "0" }),
      xcode.chain,
      xcode.leafKey,
    );
    expect((await buy(bearer("paired-dev"), fromXcode)).status).toBe(200);
    const production = await buy(
      bearer("paired-dev"),
      await appleTransaction({ environment: "Production" }),
    );
    expect(production.status).toBe(400);
  });

  it("refuses Xcode's certificate on a transaction that claims the sandbox", async () => {
    const signed = await signJws(transactionPayload(), xcode.chain, xcode.leafKey);
    expect((await buy(bearer("paired-dev"), signed)).status).toBe(400);
  });

  it("keeps a demo room's coins under demo:<code> when there is no session", async () => {
    const response = await buy({ "x-billet-demo-room": "ROOM_42-a" }, await appleTransaction());
    expect(response.status).toBe(200);
    const ledger = await Effect.runPromise(app.memory.repository.ledger(owner("demo:ROOM_42-a")));
    expect(ledger.balance).toBe(100);
    const coins = await handler(
      new Request("http://billet.test/v1/purchases", {
        headers: { "x-billet-demo-room": "ROOM_42-a" },
      }),
    );
    expect(decodeCoins(await coins.json()).balance).toBe(100);
  });

  it("gives the pair the coins when a session comes with the header", async () => {
    const response = await buy(
      { ...bearer("paired-both"), "x-billet-demo-room": "ROOM-both" },
      await appleTransaction(),
    );
    expect(response.status).toBe(200);
    const pair = await Effect.runPromise(app.memory.repository.ledger(owner("pair-paired-both")));
    const demo = await Effect.runPromise(app.memory.repository.ledger(owner("demo:ROOM-both")));
    expect([pair.balance, demo.balance]).toEqual([100, 0]);
  });

  it.each([
    ["", "empty"],
    ["a".repeat(65), "too long"],
    ["has space", "a space"],
  ])("answers 401 to a demo room code that is %s", async (code) => {
    const response = await buy({ "x-billet-demo-room": code }, await appleTransaction());
    expect(response.status).toBe(401);
  });

  describe("the mock route", () => {
    const mock = (
      body: Record<string, unknown>,
      headers: Record<string, string> = bearer("paired-mock"),
    ) => handler(post("/v1/purchases/mock", body, headers));
    const productId = "com.mikitahimpel.billet.coins.1200";

    it("credits, dedups and refunds a mock transaction", async () => {
      const transactionId = `mock-${crypto.randomUUID()}`;
      const bought = decodePurchase(
        await (await mock({ productId, transactionId, kind: "purchase" })).json(),
      );
      expect(bought).toEqual({
        transactionId,
        productId,
        coins: 1200,
        balance: 1200,
        duplicate: false,
      });
      const again = decodePurchase(
        await (await mock({ productId, transactionId, kind: "purchase" })).json(),
      );
      expect(again).toEqual({ ...bought, duplicate: true });

      const refunded = decodePurchase(
        await (await mock({ productId, transactionId, kind: "refund" })).json(),
      );
      expect(refunded).toEqual({
        transactionId,
        productId,
        coins: 1200,
        balance: 0,
        duplicate: false,
      });
      const twice = decodePurchase(
        await (await mock({ productId, transactionId, kind: "refund" })).json(),
      );
      expect(twice.duplicate).toBe(true);

      const purchase = Option.getOrThrow(
        await Effect.runPromise(app.memory.repository.findPurchase(transactionId)),
      );
      expect(purchase.environment).toBe("Mock");
    });

    it("works for a demo room", async () => {
      const transactionId = `mock-${crypto.randomUUID()}`;
      const response = await mock(
        { productId, transactionId, kind: "purchase" },
        { "x-billet-demo-room": "R1" },
      );
      expect(response.status).toBe(200);
    });

    it("answers 404 to a refund of a transaction the caller never bought", async () => {
      const response = await mock({ productId, transactionId: "mock-never", kind: "refund" });
      expect(response.status).toBe(404);
    });

    it("answers 400 InvalidPurchase to an unknown product", async () => {
      const response = await mock({ productId: "x.y", transactionId: "mock-x", kind: "purchase" });
      expect(response.status).toBe(400);
      expect(await response.json()).toEqual({ _tag: "InvalidPurchase" });
    });
  });
});

describe("with the payments flag off", () => {
  // On only for the pair `pair-paired-on`; every question is recorded.
  const asked: Array<[string, string]> = [];
  const app = setup(
    "dev",
    Layer.succeed(PaymentsSwitch, {
      enabledFor: (caller, appVersion) => {
        asked.push([caller, appVersion]);
        return Effect.succeed(caller === "pair-paired-on");
      },
    }),
  );
  afterAll(() => app.dispose());
  const { handler } = app;
  const productId = "com.mikitahimpel.billet.coins.100";

  it("answers 404 on every purchase route and changes nothing", async () => {
    const responses = [
      await handler(
        post(
          "/v1/purchases",
          { signedTransaction: await appleTransaction() },
          bearer("paired-off"),
        ),
      ),
      await handler(
        post(
          "/v1/purchases/mock",
          { productId, transactionId: "mock-flag-off", kind: "purchase" },
          bearer("paired-off"),
        ),
      ),
      await handler(
        new Request("http://billet.test/v1/purchases", { headers: bearer("paired-off") }),
      ),
      await handler(
        post(
          "/v1/purchases/mock",
          { productId, transactionId: "mock-flag-off-demo", kind: "purchase" },
          { "x-billet-demo-room": "ROOM-off" },
        ),
      ),
    ];
    expect(responses.map(({ status }) => status)).toEqual([404, 404, 404, 404]);
    expect(await responses[0]?.json()).toEqual({ _tag: "NotFound" });
    const pair = await Effect.runPromise(app.memory.repository.ledger(owner("pair-paired-off")));
    expect(pair.entries).toEqual([]);
  });

  it("asks before reading the body, so a bad body is a 404 too", async () => {
    const response = await handler(post("/v1/purchases", {}, bearer("paired-off")));
    expect(response.status).toBe(404);
  });

  it("asks about the caller's pair or demo room, with its app version", async () => {
    asked.length = 0;
    await handler(
      new Request("http://billet.test/v1/purchases", {
        headers: { ...bearer("paired-off"), "x-billet-app-version": "1.2.0+14" },
      }),
    );
    await handler(
      new Request("http://billet.test/v1/purchases", {
        headers: { "x-billet-demo-room": "ROOM-off" },
      }),
    );
    expect(asked).toEqual([
      ["pair-paired-off", "1.2.0+14"],
      ["demo:ROOM-off", "unknown"],
    ]);
  });

  it("still asks for a session first", async () => {
    const response = await handler(new Request("http://billet.test/v1/purchases"));
    expect(response.status).toBe(401);
  });

  it("serves a pair the flag is on for", async () => {
    const response = await handler(
      post(
        "/v1/purchases/mock",
        { productId, transactionId: "mock-flag-on", kind: "purchase" },
        bearer("paired-on"),
      ),
    );
    expect(response.status).toBe(200);
    expect(decodePurchase(await response.json()).balance).toBe(100);
  });

  it("leaves App Store notifications alone", async () => {
    const response = await handler(post("/v1/appstore/notifications", await notification("TEST")));
    expect(response.status).toBe(200);
  });
});

describe("App Store server notifications", () => {
  const app = setup("prod");
  afterAll(() => app.dispose());
  const { handler, memory } = app;

  const notify = (body: unknown) => handler(post("/v1/appstore/notifications", body));

  const bought = async (user: string, overrides: Record<string, unknown> = {}) => {
    const signed = await appleTransaction(overrides);
    const response = await handler(
      post("/v1/purchases", { signedTransaction: signed }, bearer(user)),
    );
    expect(response.status).toBe(200);
    return { signed, ...decodePurchase(await response.json()) };
  };

  const ledgerOf = (user: string) =>
    Effect.runPromise(memory.repository.ledger(owner(`pair-${user}`)));

  it("takes a refunded pack back, once per notification", async () => {
    const { signed, transactionId } = await bought("paired-refund");
    const body = await notification("REFUND", signed);
    const response = await notify(body);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({});
    expect((await notify(body)).status).toBe(200);

    const { balance, entries } = await ledgerOf("paired-refund");
    expect(balance).toBe(0);
    expect(entries.map(({ id, amount }) => [id, amount])).toEqual([
      [`purchase:${transactionId}`, 100],
      [`refund:${transactionId}`, -100],
    ]);
  });

  it("treats REVOKE as a refund", async () => {
    const { signed } = await bought("paired-revoke");
    expect((await notify(await notification("REVOKE", signed))).status).toBe(200);
    expect((await ledgerOf("paired-revoke")).balance).toBe(0);
  });

  it("never takes the balance below 0, and flags the purchase", async () => {
    const { signed, transactionId } = await bought("paired-spent", {
      productId: "com.mikitahimpel.billet.coins.550",
    });
    await memory.spend(owner("pair-paired-spent"), 500);
    expect((await notify(await notification("REFUND", signed))).status).toBe(200);
    expect((await ledgerOf("paired-spent")).balance).toBe(0);
    const purchase = Option.getOrThrow(
      await Effect.runPromise(memory.repository.findPurchase(transactionId)),
    );
    expect({ status: purchase.status, flagged: purchase.flagged }).toEqual({
      status: "refunded",
      flagged: 1,
    });
  });

  it("gives the coins back when Apple reverses a refund", async () => {
    const { signed, transactionId } = await bought("paired-reversed");
    await notify(await notification("REFUND", signed));
    expect((await notify(await notification("REFUND_REVERSED", signed))).status).toBe(200);
    const { balance, entries } = await ledgerOf("paired-reversed");
    expect(balance).toBe(100);
    expect(entries.map(({ id, kind }) => [id, kind])).toEqual([
      [`purchase:${transactionId}`, "purchase"],
      [`refund:${transactionId}`, "refund"],
      [`restore:${transactionId}`, "purchase"],
    ]);
  });

  it("records a refund of a transaction it never credited, and answers 200", async () => {
    const signed = await appleTransaction();
    const body = await notification("REFUND", signed);
    expect((await notify(body)).status).toBe(200);
    expect(memory.notifications().at(-1)?.outcome).toBe("unknown-transaction");
  });

  it.each([
    ["CONSUMPTION_REQUEST", "consumption-request"],
    ["TEST", "recorded"],
    ["ONE_TIME_CHARGE", "recorded"],
  ])("records %s and answers 200", async (type, outcome) => {
    const { signed } = await bought("paired-other");
    expect((await notify(await notification(type, signed))).status).toBe(200);
    expect(memory.notifications().at(-1)).toMatchObject({ type, outcome });
    expect((await ledgerOf("paired-other")).balance).toBeGreaterThan(0);
  });

  it("answers 400 to a bad signature, another bundle or another root", async () => {
    const { signed } = await bought("paired-forged");
    const good = await notification("REFUND", signed);
    const [header, payload] = good.signedPayload.split(".");
    expect((await notify({ signedPayload: `${header}.${payload}.${"A".repeat(86)}` })).status).toBe(
      400,
    );

    const otherBundle = await signJws(
      {
        ...notificationPayload("REFUND", signed),
        data: { bundleId: "com.example", environment: "Sandbox", signedTransactionInfo: signed },
      },
      apple.chain,
      apple.leafKey,
    );
    expect((await notify({ signedPayload: otherBundle })).status).toBe(400);

    const stranger = await makeChain();
    const foreign = await signJws(
      notificationPayload("REFUND", signed),
      stranger.chain,
      stranger.leafKey,
    );
    const response = await notify({ signedPayload: foreign });
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ _tag: "InvalidPurchase" });
    expect((await ledgerOf("paired-forged")).balance).toBe(100);
  });
});
