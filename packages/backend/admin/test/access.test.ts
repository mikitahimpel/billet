import { Effect, Layer } from "effect";
import { describe, expect, it } from "vitest";
import { accessConfigOf, AccessVerifier, accessVerifierLayer, denyAll } from "../src/access.ts";
import {
  cryptoLayer,
  signAccess,
  strangerKey,
  teamKeys,
  testAccess,
  unsignedAccess,
} from "./access-tokens.ts";

const verify = (token: string | null, layer = accessVerifierLayer(testAccess)) =>
  Effect.runPromise(
    Effect.gen(function* () {
      return yield* (yield* AccessVerifier).verify(token);
    }).pipe(
      Effect.provide(layer.pipe(Layer.provide(Layer.mergeAll(teamKeys, cryptoLayer)))),
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
    expect(result).toMatchObject({ _tag: "Success", success: { email: "owner@example.com" } });
  });

  it("refuses a missing token", async () => {
    await denied(null);
    await denied("");
  });

  it("refuses an expired token", async () => {
    await denied(await signAccess({ exp: Math.floor(Date.now() / 1000) - 120 }));
  });

  it("refuses a token not valid yet", async () => {
    await denied(await signAccess({ nbf: Math.floor(Date.now() / 1000) + 3_600 }));
  });

  it.each([
    ["another audience", { aud: ["b".repeat(64)] }],
    ["no audience", { aud: undefined }],
    ["another team", { iss: "https://someone-else.cloudflareaccess.com" }],
    ["no expiry", { exp: undefined }],
    ["no email (a service token)", { email: undefined, common_name: "ci" }],
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
