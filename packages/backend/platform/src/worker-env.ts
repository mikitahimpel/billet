// The bindings of the `Api` Worker. Keep in step with `env` in the root alchemy.run.ts.
export interface WorkerEnv {
  /** D1 directory: users, devices, invites and the pair lookup. */
  readonly DB: D1Database;
  /** Private R2 bucket for note images. Never served without an authorisation check. */
  readonly MEDIA: R2Bucket;
  /** One `PairRoom` Durable Object per couple. */
  readonly PAIR_ROOM: DurableObjectNamespace;
}
