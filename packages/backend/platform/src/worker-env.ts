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
  /** One `PairRoom` Durable Object per couple. */
  readonly PAIR_ROOM: DurableObjectNamespace<PairRoom>;
  /**
   * The Cloudflare Access application in front of `/admin`: team domain
   * (`<team>.cloudflareaccess.com`) and audience (AUD) tag. Missing or malformed: every `/admin`
   * request is refused. See docs/admin.md.
   */
  readonly ACCESS_TEAM_DOMAIN?: string;
  readonly ACCESS_AUD?: string;
  /** APNs auth key (PEM) and key id for demo alerts. Absent: no pushes. */
  readonly APNS_KEY?: string;
  readonly APNS_KEY_ID?: string;
  /** Temporary demo rooms. Bound on the dev stage only. */
  readonly DEMO_ROOM?: DurableObjectNamespace<DemoRoom>;
}
