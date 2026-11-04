import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthRejected, AuthUnavailable } from "@billet/backend-auth/auth-error";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { DeviceId, UserId } from "@billet/contracts-domain/ids";
import { OnboardingResponse } from "@billet/contracts-http-api/onboarding";
import { routes } from "@billet/contracts-http-api/routes";
import { OnboardingCatalogue, seedCatalogue } from "../src/catalogue.ts";
import { OnboardingUnavailable } from "../src/onboarding-error.ts";
import { OnboardingRepository } from "../src/onboarding-repository.ts";
import { OnboardingRoutes } from "../src/onboarding-routes.ts";
import { OnboardingService } from "../src/onboarding-service.ts";
import { makeInMemoryOnboardingRepository } from "./in-memory-onboarding-repository.ts";

describe("onboarding routes", () => {
  const tokenOf = (name: string) => name.padEnd(43, "x");
  const principal = (token: string): Principal => ({
    userId: Schema.decodeSync(UserId)(token),
    deviceId: Schema.decodeSync(DeviceId)(`device-${token}`),
    sessionHash: `hash-${token}`,
  });
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
        if (raw.startsWith("down")) return Effect.fail(new AuthUnavailable({ reason: "fake" }));
        return Effect.succeed(principal(raw));
      },
    }),
  );
  const memory = makeInMemoryOnboardingRepository();
  let broken = false;
  const repository: OnboardingRepository["Service"] = {
    save: (answer) =>
      broken
        ? Effect.fail(new OnboardingUnavailable({ reason: "fake" }))
        : memory.repository.save(answer),
    answersOf: memory.repository.answersOf,
  };
  const { handler, dispose } = HttpRouter.toWebHandler(
    OnboardingRoutes.pipe(
      Layer.provide(Layer.mergeAll(FakeAuth, OnboardingService.layer)),
      Layer.provide(
        Layer.mergeAll(OnboardingCatalogue.seed, Layer.succeed(OnboardingRepository, repository)),
      ),
    ),
    { disableLogger: true },
  );
  afterAll(() => dispose());

  const headers = (token?: string) =>
    token === undefined ? {} : { authorization: `Bearer ${tokenOf(token)}` };
  const get = (token?: string) =>
    handler(
      new Request(`http://billet.test${routes.getOnboarding.path}`, {
        method: routes.getOnboarding.method,
        headers: headers(token),
      }),
    );
  const post = (token: string | undefined, body: unknown) =>
    handler(
      new Request(`http://billet.test${routes.saveOnboardingAnswer.path}`, {
        method: routes.saveOnboardingAnswer.method,
        headers: { ...headers(token), "content-type": "application/json" },
        body: JSON.stringify(body),
      }),
    );
  const answer = (stepId: string, value: unknown, answeredAt = 1_000) => ({
    version: seedCatalogue.version,
    stepId,
    answer: value,
    answeredAt,
  });

  it("needs a session for both routes", async () => {
    expect((await get()).status).toBe(401);
    expect((await get("rejected-x")).status).toBe(401);
    expect((await post(undefined, answer("age", { _tag: "Skipped" }))).status).toBe(401);
    expect((await get("down-x")).status).toBe(503);
  });

  it("serves the catalogue, never cached", async () => {
    const response = await get("ana");
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(Schema.decodeUnknownSync(OnboardingResponse)(await response.json())).toEqual(
      seedCatalogue,
    );
  });

  it("stores an answer with 204, and the same answer again as one row", async () => {
    const body = answer("goals", { _tag: "Multi", options: ["widgets", "draw-together"] });
    expect((await post("ana", body)).status).toBe(204);
    expect((await post("ana", body)).status).toBe(204);
    const rows = [...memory.rows.values()].filter((row) => row.stepId === "goals");
    expect(rows).toHaveLength(1);
    expect(rows[0]?.answer).toEqual(body.answer);
  });

  it("refuses with 400 a malformed body, an unknown step and an answer that doesn't fit", async () => {
    expect((await post("ben", { stepId: "age" })).status).toBe(400);
    expect((await post("ben", answer("zodiac", { _tag: "Skipped" }))).status).toBe(400);
    expect((await post("ben", answer("age", { _tag: "Single", option: "age-99" }))).status).toBe(
      400,
    );
    expect((await post("ben", answer("age", { _tag: "Text", text: "1990" }))).status).toBe(400);
    expect(
      (
        await post(
          "ben",
          answer("goals", { _tag: "Multi", options: ["widgets", "just-exploring"] }),
        )
      ).status,
    ).toBe(400);
    expect([...memory.rows.values()].filter((row) => row.userId === tokenOf("ben"))).toEqual([]);
  });

  it("takes the app's own steps, which the catalogue doesn't serve", async () => {
    const served = Schema.decodeUnknownSync(OnboardingResponse)(await (await get("dee")).json());
    expect(served.steps.map((step) => step.id)).not.toContain("cat_coat");
    expect((await post("dee", answer("cat_coat", { _tag: "Single", option: "grey" }))).status).toBe(
      204,
    );
    expect((await post("dee", answer("cat_name", { _tag: "Text", text: "Biscuit" }))).status).toBe(
      204,
    );
    expect((await post("dee", answer("cat_name", { _tag: "Skipped" }, 2_000))).status).toBe(204);
    expect(
      (await post("dee", answer("invite_partner", { _tag: "Single", option: "sent" }))).status,
    ).toBe(204);
    expect((await post("dee", answer("invite_partner", { _tag: "Skipped" }, 2_000))).status).toBe(
      204,
    );
    expect(
      (await post("dee", answer("cat_name", { _tag: "Text", text: "x".repeat(25) }))).status,
    ).toBe(400);
    expect(
      (await post("dee", answer("invite_partner", { _tag: "Single", option: "maybe" }))).status,
    ).toBe(400);
    const own = [...memory.rows.values()].filter((row) => row.userId === tokenOf("dee"));
    expect(own.map((row) => [row.stepId, row.answer._tag]).toSorted()).toEqual([
      ["cat_coat", "Single"],
      ["cat_name", "Skipped"],
      ["invite_partner", "Skipped"],
    ]);
  });

  it("says 503 when storage is down, so the app keeps the answer queued", async () => {
    broken = true;
    try {
      expect((await post("cal", answer("age", { _tag: "Skipped" }))).status).toBe(503);
    } finally {
      broken = false;
    }
  });
});
