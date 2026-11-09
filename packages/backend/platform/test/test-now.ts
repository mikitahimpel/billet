/**
 * Override with `TEST_NOW=<ISO instant>`. Keep it in the future: workerd fires alarms on real time.
 */
export const defaultTestNow = "2099-10-31T22:42:00.000Z";

/** The instant the rooms of a test Worker run at, from its `TEST_NOW` binding. */
export const testNowOf = (env: { readonly TEST_NOW?: string }): number => {
  const now = Date.parse(env.TEST_NOW ?? defaultTestNow);
  if (Number.isNaN(now)) throw new Error(`TEST_NOW is not an instant: ${env.TEST_NOW}`);
  return now;
};
