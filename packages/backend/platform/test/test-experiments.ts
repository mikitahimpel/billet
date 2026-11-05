import { defineExperiments } from "@billet/backend-flags/experiments";

/** What the test Worker serves instead of the real registry, so a test can rely on what is running. */
export const testExperiments = defineExperiments([
  {
    key: "split",
    variants: { control: 1, bold: 1 },
    default: "control",
    exposure: 100,
    killed: false,
  },
  {
    key: "skewed",
    variants: { control: 1, loud: 3, quiet: 3 },
    default: "control",
    exposure: 100,
    killed: false,
  },
  // On for every pair in the test Worker, so the payment tests can buy; a test turns it off for one
  // pair with an override.
  {
    key: "payments",
    kind: "flag",
    variants: { off: 0, on: 1 },
    default: "on",
    exposure: 100,
    killed: false,
  },
  {
    key: "switched-off",
    variants: { control: 1, bold: 1 },
    default: "control",
    exposure: 100,
    killed: true,
  },
]);
