/**
 * The instant the test rooms live at: 22:42 UTC on a month end. Run the suite at another with
 * `TEST_NOW=<ISO instant> pnpm test`, for example on either side of midnight. Keep it far in the
 * future: workerd fires a Durable Object's alarm on the real clock, so an alarm a room sets on a
 * clock behind the real one goes off by itself, in the middle of the test.
 */
export const defaultTestNow = "2099-10-31T22:42:00.000Z";

/** The instant the rooms of a test Worker run at, from its `TEST_NOW` binding. */
export const testNowOf = (env: { readonly TEST_NOW?: string }): number => {
  const now = Date.parse(env.TEST_NOW ?? defaultTestNow);
  if (Number.isNaN(now)) throw new Error(`TEST_NOW is not an instant: ${env.TEST_NOW}`);
  return now;
};
