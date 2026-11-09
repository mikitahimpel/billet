/** A drawing phone sends points every 30–50 ms; this leaves room for begin, end and presence. */
export const maxFramesPerSecond = 60;

export interface FrameWindow {
  readonly start: number;
  readonly count: number;
}

/** `now` in ms; `admitted` is false once the window already holds the budget. */
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
