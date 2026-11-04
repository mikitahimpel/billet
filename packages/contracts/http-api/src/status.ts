import { Schema } from "effect";

/**
 * A line of text the app shows: `key` names a localized string the app may carry, and `text` is
 * what it shows when it has no such string. Both are short and plain.
 */
export const StatusMessage = Schema.Struct({
  key: Schema.String.check(
    Schema.isPattern(/^[a-z0-9]+(?:[.-][a-z0-9]+){0,7}$/),
    Schema.isMaxLength(80),
  ),
  text: Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(280)),
});
export type StatusMessage = typeof StatusMessage.Type;

/** An instant in UTC, as `2026-11-03T22:30:00Z` (seconds and milliseconds optional). */
export const StatusInstant = Schema.String.check(
  Schema.isPattern(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?Z$/),
);

/**
 * Maintenance: while `active`, the server refuses every write with 503 and this same block, and
 * the app shows a calm maintenance screen instead of errors. `until` is when it should be over, as
 * a hint for "back around …"; it does not end maintenance by itself.
 */
export const MaintenanceStatus = Schema.Struct({
  active: Schema.Boolean,
  message: Schema.optional(StatusMessage),
  until: Schema.optional(StatusInstant),
});
export type MaintenanceStatus = typeof MaintenanceStatus.Type;

/** `<marketing>` or `<marketing>+<build>`, as the app sends it in `x-billet-app-version`. */
export const AppVersion = Schema.String.check(
  Schema.isPattern(/^\d{1,4}(\.\d{1,4}){0,3}(\+\d{1,8})?$/),
);

/**
 * Product analytics (the events of `ClientEventName`). On unless `enabled` is false: then the app
 * stops reporting and drops what it was holding, and the server drops what still arrives.
 */
export const AnalyticsStatus = Schema.Struct({ enabled: Schema.Boolean });
export type AnalyticsStatus = typeof AnalyticsStatus.Type;

/**
 * What the service says to every app, signed in or not. `minVersion` is the oldest build that may
 * run: an older one shows "Update billet" and nothing else. `notice` is a soft, dismissible line.
 * Every field but `maintenance` may be absent, and a client ignores fields it does not know.
 */
export const AppStatus = Schema.Struct({
  maintenance: MaintenanceStatus,
  minVersion: Schema.optional(AppVersion),
  notice: Schema.optional(StatusMessage),
  analytics: Schema.optional(AnalyticsStatus),
});
export type AppStatus = typeof AppStatus.Type;

/** Whether the app may report events: yes unless the status says `analytics.enabled: false`. */
export const analyticsEnabled = (status: AppStatus): boolean => status.analytics?.enabled !== false;

/** No maintenance, no minimum, no notice: what is served when nothing was ever set. */
export const normalStatus: AppStatus = { maintenance: { active: false } };

/** `GET /v1/status`: needs no session, and never touches the database. */
export const StatusResponse = Schema.Struct({ status: AppStatus });
export type StatusResponse = typeof StatusResponse.Type;

/**
 * The body of the 503 every write gets during maintenance (with `Retry-After`). It is not an
 * `ApiError`: an older app reads it as a failed request and retries later, which is right.
 */
export const MaintenanceResponse = Schema.Struct({
  error: Schema.Literal("maintenance"),
  status: AppStatus,
});
export type MaintenanceResponse = typeof MaintenanceResponse.Type;
