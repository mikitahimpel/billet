import { vi } from "vitest";

// Waits for an observable event instead of sleeping a fixed time: it returns as soon as `check`
// holds and fails with a message naming what never happened.
export const waitFor = (check: () => boolean, what: string, limitMs = 4000): Promise<void> =>
  vi.waitFor(
    () => {
      if (!check()) throw new Error(`Never saw ${what}`);
    },
    { timeout: limitMs, interval: 2 },
  );
