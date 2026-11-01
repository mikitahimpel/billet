// Waits for an observable event instead of sleeping a fixed time: it returns as soon as `check`
// holds and fails with a message naming what never happened.
export const waitFor = async (
  check: () => boolean,
  what: string,
  limitMs = 4000,
): Promise<void> => {
  const end = Date.now() + limitMs;
  while (!check()) {
    if (Date.now() > end) throw new Error(`Never saw ${what}`);
    await new Promise((resolve) => setTimeout(resolve, 2));
  }
};
