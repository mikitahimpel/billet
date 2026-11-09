import { Effect, Layer, Schema } from "effect";
import { HttpRouter, HttpServerRequest, HttpServerResponse } from "effect/http";
import { reviewCodeMaxDays, ReviewService } from "@billet/backend-review/review-service";
import { CurrentAdmin } from "./admin-routes.ts";

/** The App Review pair's admin paths (docs/app-review.md). */
export const reviewAdminApi = {
  review: "/admin/api/review",
  code: "/admin/api/review/code",
  revoke: "/admin/api/review/revoke",
  wipe: "/admin/api/review/wipe",
} as const;

const IssueBody = Schema.Struct({
  days: Schema.Int.check(Schema.isBetween({ minimum: 1, maximum: reviewCodeMaxDays })),
});

const respondJson = (body: unknown, status = 200) =>
  HttpServerResponse.text(
    JSON.stringify(body, (_, value: unknown) => value ?? null),
    { status, contentType: "application/json", headers: { "cache-control": "no-store" } },
  );

const guarded = <R>(effect: Effect.Effect<HttpServerResponse.HttpServerResponse, unknown, R>) =>
  effect.pipe(
    Effect.catch((error: unknown) => {
      const tag =
        typeof error === "object" && error !== null && "_tag" in error
          ? String((error as { _tag: unknown })._tag)
          : "";
      return tag === "SchemaError" || tag === "HttpServerError"
        ? Effect.succeed(
            respondJson(
              { error: "invalid", message: "The request is not in the expected shape." },
              400,
            ),
          )
        : Effect.logError("admin review request failed", error).pipe(
            Effect.as(respondJson({ error: "unavailable" }, 503)),
          );
    }),
  );

/**
 * A new code appears only in the answer that made it; the status shows its last four symbols.
 */
export const ReviewAdminRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const review = yield* ReviewService;
    const admin = yield* CurrentAdmin;

    yield* router.add(
      "GET",
      reviewAdminApi.review,
      Effect.map(review.status, (status) => respondJson(status)).pipe(guarded),
    );
    yield* router.add(
      "POST",
      reviewAdminApi.code,
      Effect.gen(function* () {
        const { days } = yield* HttpServerRequest.schemaBodyJson(IssueBody);
        return respondJson(yield* review.issue(admin.email, days), 201);
      }).pipe(guarded),
    );
    yield* router.add(
      "POST",
      reviewAdminApi.revoke,
      review
        .revoke(admin.email)
        .pipe(Effect.as(HttpServerResponse.empty({ status: 204 })), guarded),
    );
    yield* router.add(
      "POST",
      reviewAdminApi.wipe,
      review.wipe(admin.email).pipe(Effect.as(HttpServerResponse.empty({ status: 204 })), guarded),
    );
  }),
).pipe(Layer.orDie);
