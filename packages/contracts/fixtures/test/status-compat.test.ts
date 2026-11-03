import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";
import { FlagsResponse } from "@billet/contracts-http-api/flags";
import { StatusResponse } from "@billet/contracts-http-api/status";

// The flags answer as clients before the status block decoded it.
const OldFlagsResponse = Schema.Struct({
  flags: Schema.Array(Schema.Struct({ key: ExperimentKey, variant: VariantId })),
});

const withStatus = {
  flags: [{ key: "split", variant: "a" }],
  status: {
    maintenance: { active: true, until: "2026-11-03T22:30:00Z" },
    minVersion: "1.2.0+14",
    notice: { key: "notice.slow-notes", text: "Notes may be slow tonight." },
  },
};

describe("the status block and older clients", () => {
  it("leaves a flags answer readable by a client that predates it", () => {
    expect(Schema.decodeUnknownSync(OldFlagsResponse)(withStatus)).toEqual({
      flags: [{ key: "split", variant: "a" }],
    });
  });

  it("reads a flags answer from a server that predates it", () => {
    expect(Schema.decodeUnknownSync(FlagsResponse)({ flags: [] })).toEqual({ flags: [] });
  });

  it("ignores status fields a client does not know yet", () => {
    const later = { status: { maintenance: { active: false, reason: "x" }, banner: { a: 1 } } };
    expect(Schema.decodeUnknownSync(StatusResponse)(later)).toEqual({
      status: { maintenance: { active: false } },
    });
  });

  it.each([
    ["an until without a zone", { maintenance: { active: true, until: "2026-11-03T22:30" } }],
    ["a free-text minVersion", { maintenance: { active: false }, minVersion: "latest" }],
    ["an empty notice", { maintenance: { active: false }, notice: { key: "n", text: "" } }],
  ])("refuses %s", (_, status) => {
    expect(() => Schema.decodeUnknownSync(StatusResponse)({ status })).toThrow();
  });
});
