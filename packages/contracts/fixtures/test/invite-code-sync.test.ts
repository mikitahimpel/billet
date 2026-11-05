import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { inviteCodeAlphabet, inviteCodeLength } from "@billet/contracts-domain/ids";

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
