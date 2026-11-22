import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import {
  CatEvent,
  MouseLine,
  MouseSpotId,
  mouseLineMaxScalars,
} from "@billet/contracts-domain/cat";

const line = Schema.is(MouseLine);
const spot = Schema.is(MouseSpotId);

describe("MouseLine", () => {
  it("takes 1 to 40 scalars", () => {
    expect(line("under the rug")).toBe(true);
    expect(line("💛".repeat(mouseLineMaxScalars))).toBe(true);
    expect(line("a".repeat(mouseLineMaxScalars + 1))).toBe(false);
  });

  it("refuses empty, padded and control characters", () => {
    expect(line("")).toBe(false);
    expect(line(" hi")).toBe(false);
    expect(line("hi ")).toBe(false);
    expect(line("a\nb")).toBe(false);
  });
});

describe("MouseSpotId", () => {
  it("takes a camel-case spot id", () => {
    for (const id of ["sill", "windowSeat", "catBed"]) expect(spot(id)).toBe(true);
  });

  it("refuses anything else", () => {
    for (const id of ["", "Sill", "1sill", "wind-ow", "a".repeat(25)]) expect(spot(id)).toBe(false);
  });
});

describe("the mouse events", () => {
  const decode = Schema.decodeUnknownSync(CatEvent);

  it("keeps the line optional", () => {
    expect(decode({ _tag: "MouseHidden", spot: "sill" })).toEqual({
      _tag: "MouseHidden",
      spot: "sill",
    });
  });

  it("bounds a found mouse's tries and seconds", () => {
    const found = {
      _tag: "MouseFound",
      hidden: "00000000-0000-4000-8000-000000000001",
      spot: "sill",
      tries: 1,
      seconds: 0,
    };
    expect(() => decode(found)).not.toThrow();
    expect(() => decode({ ...found, tries: 0 })).toThrow();
    expect(() => decode({ ...found, tries: 100 })).toThrow();
    expect(() => decode({ ...found, seconds: 86_401 })).toThrow();
  });
});
