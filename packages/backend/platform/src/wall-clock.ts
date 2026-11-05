// No imports: the demo Worker reads the time through this too, and must stay free of Effect.

/** Reads the wall time, in ms since the epoch. Code that stamps or compares times takes one. */
export type Now = () => number;

/** The real wall time: the one place outside Effect's Clock that reads it. */
export const systemNow: Now = () => Date.now();
