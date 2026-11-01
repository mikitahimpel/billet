import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { PairId } from "@billet/contracts-domain/pair-id";

describe("PairId", () => {
  it("decodes a non-empty string", () => {
    expect(Schema.decodeUnknownSync(PairId)("pair-1")).toBe("pair-1");
  });

  it("rejects an empty string", () => {
    expect(() => Schema.decodeUnknownSync(PairId)("")).toThrow();
  });
});
