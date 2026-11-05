import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { inviteCodeAlphabet, inviteCodeLength } from "@billet/contracts-domain/ids";
import { inviteLinkPrefix } from "@billet/contracts-http-api/routes";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "..");

// The app checks a typed code before sending it, with its own copy of the alphabet.
describe("the invite code in Swift", () => {
  const source = readFileSync(
    join(root, "packages/ios/contracts/Sources/Wire/InviteCode.swift"),
    "utf8",
  );

  it("uses the contract's alphabet", () => {
    expect(source).toContain(`public static let alphabet = "${inviteCodeAlphabet}"`);
  });

  it("uses the contract's length", () => {
    expect(source).toContain(`public static let length = ${inviteCodeLength}`);
  });
});

// The app builds the link it shares on its own, from the API's host.
describe("the invite link in Swift", () => {
  it("uses the contract's path", () => {
    const source = readFileSync(
      join(root, "apps/ios/Nooki/Onboarding/OnboardingView.swift"),
      "utf8",
    );
    expect(source).toContain(`appending(path: "${inviteLinkPrefix.slice(1)}\\(code)")`);
  });
});
