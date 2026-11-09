import type { DemoRoom } from "./demo-room-durable-object.ts";
import type { PairRoom } from "./pair-room-durable-object.ts";

// The bindings of the `Api` Worker. Keep in step with `env` in the root alchemy.run.ts.
export interface WorkerEnv {
  /** D1 directory: users, devices, invites and the pair lookup. */
  readonly DB: D1Database;
  /** Private R2 bucket for note images. Never served without an authorisation check. */
  readonly MEDIA: R2Bucket;
  /**
   * Accepted app events, no content or ids but a pair hash. Absent: events are counted in D1 only.
   */
  readonly EVENTS?: AnalyticsEngineDataset;
  /**
   * `dev` or `prod`. Picks credited App Store environments; only `dev` serves the payment extras.
   */
  readonly STAGE?: string;
  readonly PAIR_ROOM: DurableObjectNamespace<PairRoom>;
  /**
   * The Access app on `/admin`: `<team>.cloudflareaccess.com` and AUD tag. Missing: all refused.
   */
  readonly ACCESS_TEAM_DOMAIN?: string;
  readonly ACCESS_AUD?: string;
  /** The AUD tag of the Access application for agents' service tokens (`/admin/api/agent`). */
  readonly ACCESS_AGENT_AUD?: string;
  /** Read-only Account Analytics token and account. Absent: admin trends use D1 alone. */
  readonly ANALYTICS_READ_TOKEN?: string;
  readonly ANALYTICS_ACCOUNT_ID?: string;
  /**
   * Service status, outside D1 so it works while D1 is down. Absent: normal status, unchangeable.
   */
  readonly STATUS?: KVNamespace;
  /** APNs auth key (PEM) and key id, for the demo's alerts and room lanes. Absent: no pushes. */
  readonly APNS_KEY?: string;
  readonly APNS_KEY_ID?: string;
  /** `on` adds the drawing Live Activity lane. Absent or anything else: off. */
  readonly LIVE_ACTIVITY_PUSH?: string;
  /**
   * Revokes a deleting user's Apple token. Absent or empty: deletion still deletes, and logs it.
   */
  readonly APPLE_SIGN_IN_KEY?: string;
  readonly APPLE_SIGN_IN_KEY_ID?: string;
  /** TMDB's answers, for the To watch list's search and cards. Absent: kept for one request only. */
  readonly TITLES?: KVNamespace;
  /** TMDB read token. Absent or empty: `prod` answers 503, other stages a few built-in titles. */
  readonly TMDB_TOKEN?: string;
  /** Temporary demo rooms. Bound on the dev stage only. */
  readonly DEMO_ROOM?: DurableObjectNamespace<DemoRoom>;
}
