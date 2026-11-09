import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import {
  characterCount,
  Note,
  NoteSeal,
  NoteStamp,
  NoteText,
  noteTextMaxCharacters,
  noteTextMaxUnits,
  PaperColor,
  PhotoPreview,
  photoPreviewMaxLength,
  PhotoSide,
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

describe("PhotoSide", () => {
  const side = Schema.is(PhotoSide);

  it("takes whole pixels from 1 to 8192", () => {
    expect([1, 4032, 8192].map(side)).toEqual([true, true, true]);
    expect([0, -1, 8193, 1.5, Number.NaN].map(side)).toEqual([false, false, false, false, false]);
  });
});

describe("PhotoPreview", () => {
  const preview = Schema.is(PhotoPreview);

  it("takes a BlurHash as long as its header says", () => {
    // 4 by 3 components, the default of most encoders.
    expect(preview("LEHV6nWB2yk8pyo0adR*.7kCMdnj")).toBe(true);
    // 1 by 1, the smallest; and 9 by 9, the largest.
    expect(preview("00TI:j")).toBe(true);
    expect(preview(`|${"0".repeat(photoPreviewMaxLength - 1)}`)).toBe(true);
  });

  it("refuses a hash of the wrong length, outside base 83, or not a hash at all", () => {
    expect(preview("LEHV6nWB2yk8pyo0adR*.7kCMdn")).toBe(false);
    expect(preview("LEHV6nWB2yk8pyo0adR*.7kCMdnjj")).toBe(false);
    expect(preview("LEHV6nWB2yk8pyo0adR*.7kCMd/j")).toBe(false);
    expect(preview("")).toBe(false);
    // A size flag past 9 by 9.
    expect(preview(`~${"0".repeat(4 + 2 * 2 * 10 - 1)}`)).toBe(false);
    expect(preview("/9j/4AAQSkZJRgABAQ==")).toBe(false);
  });
});

describe("PaperColor", () => {
  it("is one of the five papers", () => {
    expect(PaperColor.literals).toEqual(["butter", "blush", "sage", "sky", "cream"]);
  });
});

describe("NoteStamp and NoteSeal", () => {
  // The app keeps art for each id, and a note stored with one must keep decoding.
  it("keeps every id it has had", () => {
    expect(NoteStamp.literals).toEqual(["heart", "moon", "bloom", "paw", "sun"]);
    expect(NoteSeal.literals).toEqual(["rose", "night", "meadow", "honey", "plum"]);
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

  it("decodes a photo stored before it carried a size and a preview", () => {
    const stored = { _tag: "Photo", ...base, image: "pairs/p/notes/n.png" };
    expect(decode(stored)).toEqual(stored);
  });

  it("decodes a photo with its size, preview and caption", () => {
    const photo = {
      _tag: "Photo",
      ...base,
      image: "pairs/p/notes/n.jpg",
      width: 3024,
      height: 4032,
      preview: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
      caption: "hello",
    };
    expect(decode(photo)).toEqual(photo);
    expect(() => decode({ ...photo, caption: " " })).toThrow();
    expect(() => decode({ ...photo, width: 9000 })).toThrow();
  });

  it("refuses an unknown paper and a null one", () => {
    expect(() => decode({ _tag: "Text", ...base, text: "hi", paper: "mint" })).toThrow();
    expect(() => decode({ _tag: "Text", ...base, text: "hi", paper: null })).toThrow();
  });

  it("keeps a stamp and a seal on a text note or a drawing, and refuses unknown ones", () => {
    const text = { _tag: "Text", ...base, text: "hi", stamp: "moon", seal: "rose" };
    expect(decode(text)).toMatchObject({ stamp: "moon", seal: "rose" });
    const drawing = {
      _tag: "Drawing",
      ...base,
      compact: { version: 1, strokes: [] },
      image: "pairs/p/notes/n.png",
      seal: "night",
    };
    expect(decode(drawing)).toMatchObject({ seal: "night" });
    expect(decode(drawing)).not.toHaveProperty("stamp");
    expect(() => decode({ ...text, stamp: "dragon" })).toThrow();
    expect(() => decode({ ...text, seal: null })).toThrow();
  });
});
