import { Effect, Layer, Redacted, Schema } from "effect";
import { Digest } from "effect/crypto";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthRejected, AuthUnavailable } from "@billet/backend-auth/auth-error";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { makeInMemoryPairingRepository } from "@billet/backend-pairing/test/in-memory-pairing-repository";
import { DeviceId, UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { FlagsResponse } from "@billet/contracts-http-api/flags";
import { routes } from "@billet/contracts-http-api/routes";
import { Experiments, defineExperiments } from "../src/experiments.ts";
import { FlagsRepository } from "../src/flags-repository.ts";
import { FlagsRoutes } from "../src/flags-routes.ts";
import { FlagsService } from "../src/flags-service.ts";
import { FlagConfigRepository } from "../src/flag-config-repository.ts";
import { makeInMemoryFlagConfigRepository } from "./in-memory-flag-config-repository.ts";
import { makeInMemoryFlagsRepository } from "./in-memory-flags-repository.ts";

describe("flags route", () => {
  const tokenOf = (name: string) => name.padEnd(43, "x");
  const user = (name: string) => Schema.decodeSync(UserId)(tokenOf(name));
  const principal = (token: string): Principal => ({
    userId: Schema.decodeSync(UserId)(token),
    deviceId: Schema.decodeSync(DeviceId)(`device-${token}`),
    sessionHash: `hash-${token}`,
  });
  const pairs = makeInMemoryPairingRepository();
  const FakeAuth = Layer.succeed(
    AuthService,
    AuthService.of({
      issueChallenge: Effect.die("unused"),
      signInWithApple: () => Effect.die("unused"),
      signOut: () => Effect.die("unused"),
      registerPushToken: () => Effect.die("unused"),
      authenticate: (token) => {
        const raw = Redacted.value(token);
        if (raw.startsWith("rejected")) return Effect.fail(new AuthRejected({ reason: "fake" }));
        if (raw.startsWith("down")) return Effect.fail(new AuthUnavailable({ reason: "fake" }));
        return Effect.succeed(principal(raw));
      },
    }),
  );
  const { handler, dispose } = HttpRouter.toWebHandler(
    FlagsRoutes.pipe(
      Layer.provide(Layer.mergeAll(FakeAuth, FlagsService.layer)),
      Layer.provide(
        Layer.mergeAll(
          Layer.succeed(PairingRepository, pairs.repository),
          Layer.succeed(FlagsRepository, makeInMemoryFlagsRepository().repository),
          Layer.succeed(FlagConfigRepository, makeInMemoryFlagConfigRepository().repository),
          Experiments.with(
            defineExperiments([
              {
                key: "one",
                variants: { control: 1, bold: 1 },
                default: "control",
                exposure: 100,
                killed: false,
              },
            ]),
          ),
          Digest.layerWebCrypto,
        ),
      ),
    ),
    { disableLogger: true },
  );
  afterAll(() => dispose());

  const get = (token?: string) =>
    handler(
      new Request(`http://billet.test${routes.getFlags.path}`, {
        method: routes.getFlags.method,
        headers: token === undefined ? {} : { authorization: `Bearer ${tokenOf(token)}` },
      }),
    );

  const pair = async () => {
    await Effect.runPromise(
      pairs.repository.saveInvite({
        codeHash: "h",
        ownerId: user("ana"),
        createdAt: 1,
        expiresAt: 10,
      }),
    );
    await Effect.runPromise(
      pairs.repository.claimInvite({
        codeHash: "h",
        claimerId: user("ben"),
        pairId: Schema.decodeSync(PairId)("pair-1"),
        now: 2,
      }),
    );
  };

  it("needs a signed-in caller", async () => {
    expect((await get()).status).toBe(401);
    expect((await get("rejected-x")).status).toBe(401);
  });

  it("says 503 when auth is down", async () => {
    expect((await get("down-x")).status).toBe(503);
  });

  it("lists nothing for a caller without a partner", async () => {
    const response = await get("cal");
    expect(response.status).toBe(200);
    expect(Schema.decodeUnknownSync(FlagsResponse)(await response.json())).toEqual({ flags: [] });
  });

  it("gives both partners the same list, never cached", async () => {
    await pair();
    const [one, two] = await Promise.all([get("ana"), get("ben")]);
    expect(one.headers.get("cache-control")).toBe("no-store");
    const forAna = Schema.decodeUnknownSync(FlagsResponse)(await one.json());
    const forBen = Schema.decodeUnknownSync(FlagsResponse)(await two.json());
    expect(forAna.flags).toHaveLength(1);
    expect(forBen).toEqual(forAna);
  });
});
