import { Clock, Effect } from "effect";
import type { Now } from "./wall-clock.ts";

/**
 * Effect's live `Clock`, with its wall time read from `now`. Sleep and the nanosecond clocks
 * (span timings) stay live, so with `systemNow` it behaves exactly like the default clock. A
 * Durable Object passes its own `clock()` here, so a test that fixes the object's time fixes the
 * time its Effect code sees too.
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
