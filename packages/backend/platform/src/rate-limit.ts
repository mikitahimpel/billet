import { Schema } from "effect";
import { EpochMillis } from "@billet/contracts-domain/ids";
import { ApiError } from "@billet/contracts-http-api/api-error";
import { isInviteLinkPath } from "./app-links.ts";
import { sha256Hex } from "./hashed-session-tokens.ts";
import { logLine } from "./observability.ts";
import { systemNow } from "./wall-clock.ts";

/** What a `rate_limits` row holds. A test fails if the table's columns differ. */
export const StoredRateLimit = Schema.Struct({
  bucket: Schema.String,
  windowStart: EpochMillis,
  count: Schema.Int,
});

export const windowMillis = 60_000;

/** Requests per client per window. A couple's real use is far below these. */
export const limits = {
  auth: 30,
  pairing: 20,
  media: 60,
  events: 60,
  purchases: 30,
  onboarding: 60,
  links: 30,
  // Search runs as the caller types, and the list fetches a card for each title it shows.
  titles: 120,
} as const;
export type LimitedGroup = keyof typeof limits;

export const groupOf = (pathname: string): LimitedGroup | undefined => {
  if (pathname.startsWith("/v1/auth/")) return "auth";
  if (pathname === "/v1/invites" || pathname === "/v1/invites/claim" || pathname === "/v1/pair") {
    return "pairing";
  }
  if (pathname === "/v1/events") return "events";
  if (pathname === "/v1/onboarding/answers") return "onboarding";
  if (pathname === "/v1/purchases" || pathname === "/v1/purchases/mock") return "purchases";
  if (pathname === "/v1/media" || pathname.startsWith("/v1/media/")) return "media";
  if (pathname.startsWith("/v1/titles/")) return "titles";
  if (isInviteLinkPath(pathname)) return "links";
  return undefined;
};

const tooManyRequests = (retryAfterSeconds: number): Response =>
  new Response(JSON.stringify(Schema.encodeSync(ApiError)(ApiError.cases.Unavailable.make({}))), {
    status: 429,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
      "retry-after": String(retryAfterSeconds),
    },
  });

/**
 * Counts this request against its route group and returns a 429 once the group's limit is spent.
 * Storage trouble lets the request through: a broken counter must not take the API down. The log
 * line is a fixed label.
 */
export const limitRequest = async (
  request: Request,
  db: D1Database,
  now: number = systemNow(),
): Promise<Response | undefined> => {
  const group = groupOf(new URL(request.url).pathname);
  if (group === undefined) return undefined;
  try {
    const caller = request.headers.get("cf-connecting-ip") ?? "unknown";
    const bucket = await sha256Hex(`${group}:${caller}`);
    const windowStart = now - (now % windowMillis);
    const [counted] = await db.batch<{ count: number }>([
      db
        .prepare(
          `INSERT INTO rate_limits (bucket, window_start, count) VALUES (?, ?, 1)
           ON CONFLICT (bucket, window_start) DO UPDATE SET count = count + 1
           RETURNING count`,
        )
        .bind(bucket, windowStart),
      db.prepare("DELETE FROM rate_limits WHERE window_start < ?").bind(windowStart),
    ]);
    const count = counted?.results[0]?.count ?? 0;
    if (count <= limits[group]) return undefined;
    return tooManyRequests(Math.max(1, Math.ceil((windowStart + windowMillis - now) / 1000)));
  } catch {
    logLine("warn", "rate limit counter unavailable");
    return undefined;
  }
};
