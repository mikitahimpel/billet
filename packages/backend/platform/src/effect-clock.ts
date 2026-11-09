import { Clock, Effect } from "effect";
import type { Now } from "./wall-clock.ts";

/**
 * Only wall time comes from `now`, so a test fixing a Durable Object's clock fixes Effect's too.
 */
export const clockOf = (now: Now): Clock.Clock => {
  const live = Clock.Clock.defaultValue();
  return {
    currentTimeMillisUnsafe: now,
    currentTimeMillis: Effect.sync(now),
    currentTimeNanosUnsafe: () => live.currentTimeNanosUnsafe(),
    currentTimeNanos: live.currentTimeNanos,
    monotonicTimeNanosUnsafe: () => live.monotonicTimeNanosUnsafe(),
    monotonicTimeNanos: live.monotonicTimeNanos,
    sleep: (duration) => live.sleep(duration),
  };
};
