import { Effect, Layer } from "effect";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { accessConfigOf, AccessVerifier, accessVerifierLayer, denyAll } from "../src/access.ts";
import {
  accessNow,
  cryptoLayer,
  signAccess,
  signAgent,
  strangerKey,
  testAgent,
  teamKeys,
  testAccess,
  unsignedAccess,
} from "./access-tokens.ts";

const seconds = Math.floor(accessNow / 1000);

/** Checks `token` at `accessNow`, on a fixed clock. */
const verify = (token: string | null, layer = accessVerifierLayer(testAccess)) =>
  Effect.runPromise(
    Effect.gen(function* () {
      yield* TestClock.setTime(accessNow);
      return yield* (yield* AccessVerifier).verify(token);
    }).pipe(
      Effect.provide(layer.pipe(Layer.provide(Layer.mergeAll(teamKeys, cryptoLayer)))),
      Effect.provide(TestClock.layer()),
      Effect.result,
    ),
  );

const denied = async (token: string | null) => {
  const result = await verify(token);
  expect(result._tag).toBe("Failure");
};

describe("the Access check", () => {
  it("lets in a valid token for the team and audience, as its email", async () => {
    const result = await verify(await signAccess({ email: "Owner@Example.com" }));
    expect(result).toMatchObject({
      _tag: "Success",
      success: { kind: "person", email: "owner@example.com" },
    });
  });

  it("lets in a service token for the agent audience, as its common_name", async () => {
    const result = await verify(await signAgent());
    expect(result).toMatchObject({
      _tag: "Success",
      success: { kind: "agent", commonName: testAgent },
    });
  });

  it("refuses a service token when no agent audience is configured", async () => {
    const result = await verify(
      await signAgent(),
      accessVerifierLayer({ ...testAccess, agentAudience: undefined }),
    );
    expect(result._tag).toBe("Failure");
  });

  it.each([
    ["a service token for the panel's audience", () => signAgent({ aud: ["a".repeat(64)] })],
    ["a person for the agent audience only", () => signAccess({ aud: ["c".repeat(64)] })],
    ["a service token that is expired", () => signAgent({ exp: seconds - 1 })],
    [
      "a service token from another team",
      () => signAgent({ iss: "https://x.cloudflareaccess.com" }),
    ],
    ["a service token with an empty common_name", () => signAgent({ common_name: "" })],
    ["a token with neither email nor common_name", () => signAgent({ common_name: undefined })],
  ])("refuses %s", async (_, token) => {
    await denied(await token());
  });

  it("refuses a service token signed by a key the team never published", async () => {
    await denied(
      await signAccess(
        { email: undefined, common_name: testAgent, aud: ["c".repeat(64)] },
        strangerKey,
      ),
    );
  });

  it("refuses a missing token", async () => {
    await denied(null);
    await denied("");
  });

  it("refuses an expired token", async () => {
    await denied(await signAccess({ exp: seconds - 1 }));
  });

  it("refuses a token not valid yet", async () => {
    await denied(await signAccess({ nbf: seconds + 120 }));
  });

  it("takes a token up to the second before `exp` and from the second of `nbf`", async () => {
    expect((await verify(await signAccess({ exp: seconds + 1 })))._tag).toBe("Success");
    expect((await verify(await signAccess({ nbf: seconds })))._tag).toBe("Success");
    await denied(await signAccess({ exp: seconds }));
    await denied(await signAccess({ nbf: seconds + 1 }));
  });

  it.each([
    ["another audience", { aud: ["b".repeat(64)] }],
    ["no audience", { aud: undefined }],
    ["another team", { iss: "https://someone-else.cloudflareaccess.com" }],
    ["no expiry", { exp: undefined }],
    ["an empty email", { email: "" }],
  ])("refuses %s", async (_, overrides) => {
    await denied(await signAccess(overrides));
  });

  it("refuses a token signed by a key the team never published", async () => {
    await denied(await signAccess({}, strangerKey));
  });

  it("refuses an unsigned token and garbage", async () => {
    await denied(unsignedAccess());
    await denied("not.a.jwt");
    const valid = await signAccess();
    await denied(`${valid.slice(0, -4)}AAAA`);
  });

  it("refuses everything when not configured", async () => {
    const result = await Effect.runPromise(
      Effect.gen(function* () {
        return yield* (yield* AccessVerifier).verify(yield* Effect.promise(() => signAccess()));
      }).pipe(Effect.provide(denyAll), Effect.result),
    );
    expect(result._tag).toBe("Failure");
  });
});

describe("accessConfigOf", () => {
  it("reads a team domain and an AUD tag", () => {
    expect(accessConfigOf(" Billet.cloudflareaccess.com ", "A".repeat(64))).toEqual({
      teamDomain: "billet.cloudflareaccess.com",
      audience: "a".repeat(64),
    });
  });

  it("reads an agent AUD tag, and drops a malformed one without closing the panel", () => {
    const team = "billet.cloudflareaccess.com";
    expect(accessConfigOf(team, "a".repeat(64), " " + "C".repeat(64))?.agentAudience).toBe(
      "c".repeat(64),
    );
    const config = accessConfigOf(team, "a".repeat(64), "not-hex");
    expect(config?.audience).toBe("a".repeat(64));
    expect(config?.agentAudience).toBeUndefined();
  });

  it.each([
    [undefined, "a".repeat(64)],
    ["billet.cloudflareaccess.com", undefined],
    ["", ""],
    ["billet.example.com", "a".repeat(64)],
    ["https://billet.cloudflareaccess.com", "a".repeat(64)],
    ["billet.cloudflareaccess.com", "not-hex"],
  ])("fails closed on %j / %j", (team, aud) => {
    expect(accessConfigOf(team, aud)).toBeUndefined();
  });
});
