/**
 * Pure: decides which note went to which lane and how far. The Durable Object persists and alarms.
 */
export type DeliveryStatus = "pending" | "delivered" | "abandoned";

export interface DeliveryEntry {
  readonly noteId: string;
  readonly lane: string;
  readonly status: DeliveryStatus;
  /** Attempts that ended in "retry" so far. */
  readonly attempts: number;
  /** Epoch millis. Meaningful while `pending`. */
  readonly nextAttemptAt: number;
}

/** What one try of a lane reported. */
export type DeliveryOutcome = "Delivered" | "Retry" | "Abandon";

export const maxAttempts = 5;
const firstBackoffMillis = 5_000;
const longestBackoffMillis = 15 * 60_000;

/** Wait before the next try, after `attempts` failures: 5 s, 10 s, 20 s, ... up to 15 minutes. */
export const backoffMillis = (attempts: number): number =>
  Math.min(firstBackoffMillis * 2 ** Math.max(0, attempts - 1), longestBackoffMillis);

/** A pair that already has an entry gets it back unchanged, so a resend never delivers twice. */
export const enqueue = (
  existing: DeliveryEntry | undefined,
  noteId: string,
  lane: string,
  now: number,
): DeliveryEntry =>
  existing ?? { noteId, lane, status: "pending", attempts: 0, nextAttemptAt: now };

export const isDue = (entry: DeliveryEntry, now: number): boolean =>
  entry.status === "pending" && entry.nextAttemptAt <= now;

/**
 * Only a pending entry changes; late reports are ignored. The `maxAttempts`th retry abandons it.
 */
export const settle = (
  entry: DeliveryEntry,
  outcome: DeliveryOutcome,
  now: number,
): DeliveryEntry => {
  if (entry.status !== "pending") return entry;
  switch (outcome) {
    case "Delivered":
      return { ...entry, status: "delivered" };
    case "Abandon":
      return { ...entry, status: "abandoned" };
    case "Retry": {
      const attempts = entry.attempts + 1;
      return attempts >= maxAttempts
        ? { ...entry, status: "abandoned", attempts }
        : { ...entry, attempts, nextAttemptAt: now + backoffMillis(attempts) };
    }
  }
};

export interface LaneHealth {
  readonly delivered: number;
  readonly abandoned: number;
  readonly pending: number;
  /** Delivered over finished (delivered + abandoned); nothing until one has finished. */
  readonly successRate: number | undefined;
}

/** How each lane is doing, from the entries of one room. */
export const deliveryHealth = (
  entries: ReadonlyArray<DeliveryEntry>,
): Readonly<Record<string, LaneHealth>> => {
  const counts: Record<string, { delivered: number; abandoned: number; pending: number }> = {};
  for (const { lane, status } of entries) {
    const bucket = (counts[lane] ??= { delivered: 0, abandoned: 0, pending: 0 });
    bucket[status] += 1;
  }
  return Object.fromEntries(
    Object.entries(counts).map(([lane, c]) => {
      const finished = c.delivered + c.abandoned;
      return [lane, { ...c, successRate: finished === 0 ? undefined : c.delivered / finished }];
    }),
  );
};

/** When the alarm should next fire, or nothing when no entry is pending. */
export const nextAlarmAt = (entries: ReadonlyArray<DeliveryEntry>): number | undefined => {
  const times = entries.filter((e) => e.status === "pending").map((e) => e.nextAttemptAt);
  return times.length === 0 ? undefined : Math.min(...times);
};
