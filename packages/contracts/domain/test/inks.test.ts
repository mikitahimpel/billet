import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { freeInk, InkId, inkOf, inks } from "@billet/contracts-domain/inks";
import { Note } from "@billet/contracts-domain/note";

describe("inks", () => {
  it("have unique ids, and exactly one is free: the default", () => {
    expect(new Set(inks.map(({ id }) => id)).size).toBe(inks.length);
    expect(inks.filter(({ price }) => price === 0).map(({ id }) => id)).toEqual([freeInk]);
    for (const { price } of inks) expect(price).toBeGreaterThanOrEqual(0);
  });

  it("names ids ink-<word>", () => {
    expect(Schema.decodeUnknownSync(InkId)("ink-sea-glass")).toBe("ink-sea-glass");
    for (const bad of ["rose", "ink-", "ink-Rose", "ink_rose", `ink-${"a".repeat(40)}`]) {
      expect(() => Schema.decodeUnknownSync(InkId)(bad), bad).toThrow();
    }
  });

  it("finds an ink by id", () => {
    expect(inkOf("ink-rose")?.name).toBe("Rose");
    expect(inkOf("ink-unknown")).toBeUndefined();
  });
});

describe("a text note's ink", () => {
  const stored = { _tag: "Text", id: "note-1", author: "user-a", sentAt: 1, text: "hi" };

  it("reads a note from before inks as the free ink, and writes it out", () => {
    const note = Schema.decodeUnknownSync(Note)(stored);
    expect(note).toMatchObject({ _tag: "Text", ink: freeInk });
    expect(Schema.encodeSync(Note)(note)).toMatchObject({ ink: "ink-graphite" });
  });

  it("keeps the ink it was written in", () => {
    expect(Schema.decodeUnknownSync(Note)({ ...stored, ink: "ink-rose" })).toMatchObject({
      ink: "ink-rose",
    });
  });

  it("refuses an ink the catalog does not sell", () => {
    expect(() => Schema.decodeUnknownSync(Note)({ ...stored, ink: "ink-unknown" })).toThrow();
  });
});
