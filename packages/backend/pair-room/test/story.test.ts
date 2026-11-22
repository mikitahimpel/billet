import { Effect, Layer, Schema } from "effect";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import type { UserId } from "@billet/contracts-domain/ids";
import { StoryId, type StoryMarkKind } from "@billet/contracts-domain/story";
import { RoomStore } from "../src/room-store.ts";
import {
  decideStory,
  type StoryRow,
  StoryRoom,
  StoryStore,
  storyMarksInAll,
  storyMarksPerEpisode,
  storyView,
} from "../src/story.ts";
import { active, alice, bob, mallory, vacant } from "./samples.ts";

const id = Schema.decodeUnknownSync(StoryId);
const episode = id("fish-plush");
const request = (kind: StoryMarkKind, ref: string, of = episode) => ({
  episode: of,
  kind,
  ref: id(ref),
});

const apply = (
  rows: ReadonlyArray<StoryRow>,
  by: UserId,
  kind: StoryMarkKind,
  ref: string,
  at = 1,
) => {
  const decision = decideStory(rows, by, request(kind, ref), at);
  return decision._tag === "Write" ? [...rows, decision.write] : rows;
};

describe("story marks", () => {
  it("keeps a found clue once, whoever repeats it", () => {
    let rows = apply([], alice, "found", "empty-basket");
    expect(decideStory(rows, alice, request("found", "empty-basket"), 2)).toEqual({
      _tag: "Keep",
    });
    rows = apply(rows, bob, "found", "empty-basket", 3);
    expect(rows).toHaveLength(2);
  });

  it("keeps the first named suspect and ignores a second, even another one", () => {
    const rows = apply([], alice, "named", "crow");
    expect(decideStory(rows, alice, request("named", "snail"), 2)).toEqual({ _tag: "Keep" });
    expect(decideStory(rows, alice, request("named", "crow"), 2)).toEqual({ _tag: "Keep" });
    expect(decideStory(rows, bob, request("named", "snail"), 2)._tag).toBe("Write");
    expect(decideStory(rows, alice, request("named", "snail", id("other")), 2)._tag).toBe("Write");
  });

  it("refuses a member's 41st mark in an episode and 401st in all, and lets the partner on", () => {
    let rows: ReadonlyArray<StoryRow> = [];
    for (let beat = 0; beat < storyMarksPerEpisode; beat++) {
      rows = apply(rows, alice, "found", `beat-${beat}`);
    }
    expect(decideStory(rows, alice, request("found", "one-more"), 2)).toEqual({ _tag: "Full" });
    expect(decideStory(rows, alice, request("found", "beat-3"), 2)).toEqual({ _tag: "Keep" });
    expect(decideStory(rows, bob, request("found", "one-more"), 2)._tag).toBe("Write");

    const many: ReadonlyArray<StoryRow> = Array.from({ length: storyMarksInAll }, (_, n) => ({
      member: alice,
      episode: id(`episode-${Math.floor(n / storyMarksPerEpisode)}`),
      kind: "found" as const,
      ref: id(`beat-${n}`),
      at: n,
    }));
    expect(many).toHaveLength(storyMarksInAll);
    expect(decideStory(many, alice, request("found", "beat-x", id("episode-new")), 2)).toEqual({
      _tag: "Full",
    });
  });

  it("shows the partner's found clues at once and their named suspect only after your own", () => {
    let rows = apply([], alice, "found", "sill", 1);
    rows = apply(rows, alice, "named", "crow", 2);
    rows = apply(rows, alice, "named", "snail", 3);
    expect(storyView(rows, bob)).toEqual({
      mine: [],
      partner: [{ episode, kind: "found", ref: "sill", at: 1 }],
    });
    rows = apply(rows, bob, "named", "snail", 4);
    expect(storyView(rows, bob).partner.map((mark) => mark.ref)).toEqual(["sill", "crow"]);
    expect(storyView(rows, alice).partner.map((mark) => mark.ref)).toEqual(["snail"]);
  });

  it("waits for a suspect named in the same episode, not another", () => {
    let rows = apply([], alice, "named", "crow");
    rows = [...rows, { member: bob, episode: id("other"), kind: "named", ref: id("x"), at: 2 }];
    expect(storyView(rows, bob).partner).toEqual([]);
  });
});

describe("StoryRoom", () => {
  const roomWith = (state: typeof active | typeof vacant) => {
    let rows: ReadonlyArray<StoryRow> = [];
    const store = Layer.succeed(StoryStore, {
      all: Effect.sync(() => rows),
      put: (row) => Effect.sync(() => void (rows = [...rows, row])),
      forget: Effect.sync(() => void (rows = [])),
    });
    const room = Layer.succeed(RoomStore, {
      load: Effect.succeed(state),
    } as unknown as RoomStore["Service"]);
    return Effect.runSync(StoryRoom.make.pipe(Effect.provide(Layer.merge(store, room))));
  };
  const at = <A>(millis: number, effect: Effect.Effect<A>) =>
    Effect.runPromise(
      TestClock.setTime(millis).pipe(Effect.andThen(effect), Effect.provide(TestClock.layer())),
    );
  const mark = (kind: StoryMarkKind, ref: string) =>
    ({ _tag: "Mark", ...request(kind, ref) }) as const;

  it("stamps the room's clock, answers the caller's view, and refuses strangers and a vacant room", async () => {
    const story = roomWith(active);
    expect(await at(5_000, story.run(alice, mark("found", "empty-basket")))).toEqual({
      _tag: "Done",
      view: { mine: [{ episode, kind: "found", ref: "empty-basket", at: 5_000 }], partner: [] },
    });
    expect(await at(6_000, story.run(bob, { _tag: "View" }))).toMatchObject({
      view: { partner: [{ ref: "empty-basket" }] },
    });
    expect(await at(6_000, story.run(mallory, { _tag: "View" }))).toEqual({
      _tag: "Refused",
      reason: "NotOpen",
    });
    expect(await at(6_000, roomWith(vacant).run(alice, { _tag: "View" }))).toEqual({
      _tag: "Refused",
      reason: "NotOpen",
    });
  });

  it("forgets every mark", async () => {
    const story = roomWith(active);
    await at(1, story.run(alice, mark("found", "empty-basket")));
    await at(2, story.forget);
    expect(await at(3, story.run(alice, { _tag: "View" }))).toEqual({
      _tag: "Done",
      view: { mine: [], partner: [] },
    });
  });
});
