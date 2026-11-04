import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import {
  characterCount,
  Note,
  NoteText,
  noteTextMaxCharacters,
  noteTextMaxUnits,
  PaperColor,
} from "@billet/contracts-domain/note";

const accepts = Schema.is(NoteText);

describe("NoteText", () => {
  it("takes 1 to 120 characters", () => {
    expect(accepts("hi")).toBe(true);
    expect(accepts("a".repeat(noteTextMaxCharacters))).toBe(true);
    expect(accepts("a".repeat(noteTextMaxCharacters + 1))).toBe(false);
  });

  it("refuses an empty or whitespace-only note", () => {
    expect(accepts("")).toBe(false);
    expect(accepts("  \n\t")).toBe(false);
  });

  it("counts characters as a person does, so emoji count once", () => {
    const family = "👩‍👩‍👧‍👦";
    expect(characterCount(family)).toBe(1);
    expect(characterCount("é")).toBe(1);
    expect(accepts(family.repeat(noteTextMaxCharacters))).toBe(true);
    expect(accepts("💛".repeat(noteTextMaxCharacters + 1))).toBe(false);
  });

  it("caps UTF-16 units, so combining marks can't stretch one character", () => {
    expect(accepts(`a${"́".repeat(noteTextMaxUnits)}`)).toBe(false);
  });
});

describe("PaperColor", () => {
  it("is one of the five papers", () => {
    expect(PaperColor.literals).toEqual(["butter", "blush", "sage", "sky", "cream"]);
  });
});

describe("Note", () => {
  const decode = Schema.decodeUnknownSync(Note);
  const base = { id: "n", author: "u", sentAt: 0 };

  it("decodes a text note with or without paper", () => {
    expect(decode({ _tag: "Text", ...base, text: "hi", paper: "sky" })).toMatchObject({
      paper: "sky",
    });
    expect(decode({ _tag: "Text", ...base, text: "hi" })).not.toHaveProperty("paper");
  });

  it("refuses an unknown paper and a null one", () => {
    expect(() => decode({ _tag: "Text", ...base, text: "hi", paper: "mint" })).toThrow();
    expect(() => decode({ _tag: "Text", ...base, text: "hi", paper: null })).toThrow();
  });
});
