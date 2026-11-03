import { Context, Data, type Effect } from "effect";
import type { AppStatus } from "@billet/contracts-http-api/status";

/** The service status as last saved, with who saved it. Version 0 means it was never set. */
export interface StoredAppStatus {
  readonly status: AppStatus;
  readonly version: number;
  readonly updatedAt: number | null;
  readonly updatedBy: string | null;
}

/** One saved change: the whole status as it was set, by whom and when. */
export interface AppStatusChange {
  readonly version: number;
  readonly at: number;
  readonly by: string;
  readonly status: AppStatus;
}

/** Someone saved the status since this version was read. */
export class AppStatusConflict extends Data.TaggedError("AppStatusConflict")<{
  readonly current: number;
}> {}

/** The store could not be read or written. `reason` is a fixed label. */
export class AppStatusUnavailable extends Data.TaggedError("AppStatusUnavailable")<{
  readonly reason: string;
}> {}

/**
 * Where the service status lives. Not in the database: maintenance has to be switched on, and
 * read, while the database is down (Workers KV in the platform package).
 */
export class AppStatusStore extends Context.Service<
  AppStatusStore,
  {
    readonly current: Effect.Effect<StoredAppStatus, AppStatusUnavailable>;
    /** Newest first. */
    readonly history: (
      limit: number,
    ) => Effect.Effect<ReadonlyArray<AppStatusChange>, AppStatusUnavailable>;
    readonly save: (input: {
      readonly status: AppStatus;
      readonly expectedVersion: number;
      readonly by: string;
      readonly at: number;
    }) => Effect.Effect<StoredAppStatus, AppStatusConflict | AppStatusUnavailable>;
  }
>()("@billet/backend-admin/AppStatusStore") {}
