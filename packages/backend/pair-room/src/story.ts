import { Clock, Context, Effect, Layer, Schema, Semaphore } from "effect";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { StoryId, StoryMark, StoryMarkKind } from "@billet/contracts-domain/story";
import { StoryMarkRequest, StoryResponse } from "@billet/contracts-http-api/story";
import { RoomStore } from "./room-store.ts";

/** Marks one member may hold in one episode, and in all. */
export const storyMarksPerEpisode = 40;
export const storyMarksInAll = 400;

/** One member's mark, as the room stores it. */
export const StoryRow = Schema.Struct({
  member: UserId,
  episode: StoryId,
  kind: StoryMarkKind,
  ref: StoryId,
  at: EpochMillis,
});
export type StoryRow = typeof StoryRow.Type;

const markOf = ({ episode, kind, ref, at }: StoryRow): StoryMark => ({ episode, kind, ref, at });

/** What a mark does: the row to store, if anything changes, or that the member holds too many. */
export type StoryDecision =
  | { readonly _tag: "Keep" }
  | { readonly _tag: "Write"; readonly write: StoryRow }
  | { readonly _tag: "Full" };

/**
 * Pure. A mark already held changes nothing, and a second `named` in an episode never replaces
 * the first, so a retry or a change of mind cannot move what the partner is waiting on.
 */
export const decideStory = (
  rows: ReadonlyArray<StoryRow>,
  by: UserId,
  request: StoryMarkRequest,
  at: EpochMillis,
): StoryDecision => {
  const mine = rows.filter((row) => row.member === by);
  const inEpisode = mine.filter((row) => row.episode === request.episode);
  if (request.kind === "named" && inEpisode.some((row) => row.kind === "named")) {
    return { _tag: "Keep" };
  }
  if (inEpisode.some((row) => row.kind === request.kind && row.ref === request.ref)) {
    return { _tag: "Keep" };
  }
  if (inEpisode.length >= storyMarksPerEpisode || mine.length >= storyMarksInAll) {
    return { _tag: "Full" };
  }
  return {
    _tag: "Write",
    write: { member: by, episode: request.episode, kind: request.kind, ref: request.ref, at },
  };
};

/** The marks as `caller` sees them. The partner's `named` marks wait for the caller's own. */
export const storyView = (rows: ReadonlyArray<StoryRow>, caller: UserId): StoryResponse => {
  const named = new Set(
    rows.filter((row) => row.member === caller && row.kind === "named").map((row) => row.episode),
  );
  const byTime = (a: StoryRow, b: StoryRow) => a.at - b.at;
  return {
    mine: rows
      .filter((row) => row.member === caller)
      .toSorted(byTime)
      .map(markOf),
    partner: rows
      .filter((row) => row.member !== caller && (row.kind === "found" || named.has(row.episode)))
      .toSorted(byTime)
      .map(markOf),
  };
};

/** The marks of one room. Failures are defects, as for `RoomStore`. */
export class StoryStore extends Context.Service<
  StoryStore,
  {
    readonly all: Effect.Effect<ReadonlyArray<StoryRow>>;
    readonly put: (row: StoryRow) => Effect.Effect<void>;
    /** Deletes every mark: the pair is ending. */
    readonly forget: Effect.Effect<void>;
  }
>()("@billet/backend-pair-room/StoryStore") {}

export const StoryCommand = Schema.TaggedUnion({
  View: {},
  Mark: { episode: StoryId, kind: StoryMarkKind, ref: StoryId },
});
export type StoryCommand = typeof StoryCommand.Type;

/** The caller's marks after a command, that the room is not open, or that the member holds too many. */
export const StoryResult = Schema.TaggedUnion({
  Done: { view: StoryResponse },
  Refused: { reason: Schema.Literals(["NotOpen", "Full"]) },
});
export type StoryResult = typeof StoryResult.Type;

/** Runs story commands against one room: load, decide, store, view. */
export class StoryRoom extends Context.Service<StoryRoom>()("@billet/backend-pair-room/StoryRoom", {
  make: Effect.gen(function* () {
    const store = yield* StoryStore;
    const room = yield* RoomStore;
    const lock = yield* Semaphore.make(1);

    const run = (by: UserId, command: StoryCommand): Effect.Effect<StoryResult> =>
      Effect.gen(function* () {
        const state = yield* room.load;
        if (state._tag !== "Active" || !state.members.some((member) => member.user === by)) {
          return StoryResult.cases.Refused.make({ reason: "NotOpen" });
        }
        const rows = yield* store.all;
        if (command._tag === "View") {
          return StoryResult.cases.Done.make({ view: storyView(rows, by) });
        }
        const { _tag, ...request } = command;
        const decision = decideStory(rows, by, request, yield* Clock.currentTimeMillis);
        switch (decision._tag) {
          case "Keep":
            return StoryResult.cases.Done.make({ view: storyView(rows, by) });
          case "Full":
            return StoryResult.cases.Refused.make({ reason: "Full" });
          case "Write":
            yield* store.put(decision.write);
            return StoryResult.cases.Done.make({
              view: storyView([...rows, decision.write], by),
            });
        }
      }).pipe(lock.withPermits(1));

    return { run, forget: store.forget.pipe(lock.withPermits(1)) };
  }),
}) {
  static readonly layer = Layer.effect(StoryRoom, StoryRoom.make);
}
