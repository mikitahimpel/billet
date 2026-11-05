import type { DemoRoom } from "./demo-room-durable-object.ts";
import type { PairRoom } from "./pair-room-durable-object.ts";

// The bindings of the `Api` Worker. Keep in step with `env` in the root alchemy.run.ts.
export interface WorkerEnv {
  /** D1 directory: users, devices, invites and the pair lookup. */
  readonly DB: D1Database;
  /** Private R2 bucket for note images. Never served without an authorisation check. */
  readonly MEDIA: R2Bucket;
  /**
   * Workers Analytics Engine dataset for accepted app events (no content, no ids but a pair hash).
   * Optional so a Worker without it still serves; then events are only counted in D1.
   */
  readonly EVENTS?: AnalyticsEngineDataset;
  /**
   * The Alchemy stage this Worker was deployed as (`dev`, `prod`). Shown in the admin panel. It
   * also decides which App Store environments are credited, and only `dev` serves the payment
   * extras: Xcode transactions, mock purchases and demo-room callers (docs/payments.md).
   */
  readonly STAGE?: string;
  /** One `PairRoom` Durable Object per couple. */
  readonly PAIR_ROOM: DurableObjectNamespace<PairRoom>;
  /**
   * The Cloudflare Access application in front of `/admin`: team domain
   * (`<team>.cloudflareaccess.com`) and audience (AUD) tag. Missing or malformed: every `/admin`
   * request is refused. See docs/admin.md.
   */
  readonly ACCESS_TEAM_DOMAIN?: string;
  readonly ACCESS_AUD?: string;
  /** The AUD tag of the Access application for agents' service tokens (`/admin/api/agent`). */
  readonly ACCESS_AGENT_AUD?: string;
  /**
   * A Cloudflare API token that can only read Account Analytics, and the account, for the admin's
   * trends from Analytics Engine. Absent: the trends use D1 alone.
   */
  readonly ANALYTICS_READ_TOKEN?: string;
  readonly ANALYTICS_ACCOUNT_ID?: string;
  /**
   * The service status (maintenance, minimum build, notice), kept apart from D1 so it works while
   * the database is down. Absent: the normal status, and the admin panel can't change it.
   */
  readonly STATUS?: KVNamespace;
  /**
   * APNs auth key (PEM) and key id, for the demo's alerts and the PairRoom's widget and alert
   * lanes. Absent: no pushes.
   */
  readonly APNS_KEY?: string;
  readonly APNS_KEY_ID?: string;
  /** `on` adds the drawing Live Activity lane. Absent or anything else: off. */
  readonly LIVE_ACTIVITY_PUSH?: string;
  /**
   * Sign in with Apple key (PEM) and key id, for revoking a user's Apple token when they delete
   * their account. Absent or empty: deletion still deletes, and logs that nothing was revoked.
   */
  readonly APPLE_SIGN_IN_KEY?: string;
  readonly APPLE_SIGN_IN_KEY_ID?: string;
  /** Temporary demo rooms. Bound on the dev stage only. */
  readonly DEMO_ROOM?: DurableObjectNamespace<DemoRoom>;
}
