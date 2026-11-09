import { Schema } from "effect";

/** `key` names a localized string the app may carry; `text` is shown when it has none. */
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
 * While `active`, every write gets 503 with this block. `until` is only a hint, it ends nothing.
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
 * When `enabled` is false the app stops reporting and drops its queue; the server drops the rest.
 */
export const AnalyticsStatus = Schema.Struct({ enabled: Schema.Boolean });
export type AnalyticsStatus = typeof AnalyticsStatus.Type;

/**
 * Older than `minVersion` shows only "Update billet". Clients ignore fields they don't know.
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

export const normalStatus: AppStatus = { maintenance: { active: false } };

/** `GET /v1/status`: needs no session, and never touches the database. */
export const StatusResponse = Schema.Struct({ status: AppStatus });
export type StatusResponse = typeof StatusResponse.Type;

/** The 503 body (with `Retry-After`), not an `ApiError`, so an older app retries later. */
export const MaintenanceResponse = Schema.Struct({
  error: Schema.Literal("maintenance"),
  status: AppStatus,
});
export type MaintenanceResponse = typeof MaintenanceResponse.Type;
