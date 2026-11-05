/**
 * Frames one socket may send per second. A drawing phone sends a points batch every 30 to 50 ms,
 * so this leaves room for begin, end and presence; frames past it are dropped.
 */
export const maxFramesPerSecond = 60;

/** A fixed one-second window of the frames one socket sent. */
export interface FrameWindow {
  readonly start: number;
  readonly count: number;
}

/** Counts one frame at `now` (ms); `admitted` is false once the window already holds the budget. */
export const admitFrame = (
  window: FrameWindow | undefined,
  now: number,
): { readonly window: FrameWindow; readonly admitted: boolean } => {
  if (window === undefined || now - window.start >= 1000 || now < window.start) {
    return { window: { start: now, count: 1 }, admitted: true };
  }
  const count = window.count + 1;
  return { window: { start: window.start, count }, admitted: count <= maxFramesPerSecond };
};
