import { Clock, Context, Effect, Layer, Option, Schema, Semaphore } from "effect";
import { IdempotencyKey, MediaKey, type UserId } from "@billet/contracts-domain/ids";
import { CoinEntryId } from "@billet/contracts-domain/coins";
import { CompactStrokes } from "@billet/contracts-domain/ink";
import { Riddle, RiddleId } from "@billet/contracts-domain/riddle";
import { RiddlesResponse } from "@billet/contracts-http-api/riddle";
import {
  decideGiveUp,
  decideGuess,
  decideHint,
  decideSend,
  type RiddleDecision,
  type RiddleGuessRow,
  RiddleRefusal,
  type RiddleRow,
  type RiddleSeries,
  riddleView,
} from "./riddle-rules.ts";
import type { RoomDecision } from "./room-decision.ts";
import { RoomService } from "./room-service.ts";
import { RoomStore } from "./room-store.ts";

/** How many ended riddles the board is sent. */
export const endedRiddleLimit = 20;

/**
 * Read-only: the room's commit writes riddles, so an end, its entry and its coins land together.
 */
export class RiddleStore extends Context.Service<
  RiddleStore,
  {
    readonly byId: (id: RiddleId) => Effect.Effect<Option.Option<RiddleRow>>;
    /** Every riddle not ended yet, oldest first. */
    readonly open: Effect.Effect<ReadonlyArray<RiddleRow>>;
    /** The latest `limit` riddles that ended, the latest end first. */
    readonly ended: (limit: number) => Effect.Effect<ReadonlyArray<RiddleRow>>;
    readonly guess: (
      riddle: RiddleId,
      key: IdempotencyKey,
    ) => Effect.Effect<Option.Option<RiddleGuessRow>>;
    readonly series: Effect.Effect<RiddleSeries>;
    /** Deletes every riddle, try and the series: the pair is ending. */
    readonly forget: Effect.Effect<void>;
  }
>()("@billet/backend-pair-room/RiddleStore") {}

export const RiddleCommand = Schema.TaggedUnion({
  View: {},
  Send: {
    id: RiddleId,
    word: Schema.String,
    compact: CompactStrokes,
    image: MediaKey,
  },
  Guess: { riddle: RiddleId, key: IdempotencyKey, guess: Schema.String },
  Hint: { riddle: RiddleId },
  GiveUp: { riddle: RiddleId },
});
export type RiddleCommand = typeof RiddleCommand.Type;

/** What a draw-guess command answers: the riddles, the riddle after it, or why it was refused. */
export const RiddleResult = Schema.TaggedUnion({
  Listed: { view: RiddlesResponse },
  /** `right` answers a try. */
  Changed: { riddle: Riddle, right: Schema.optionalKey(Schema.Boolean) },
  Refused: { reason: RiddleRefusal },
});
export type RiddleResult = typeof RiddleResult.Type;

/** What a command did, for the room to tell the sockets, the push lanes and the shop. */
export interface RiddleOutcome {
  readonly result: RiddleResult;
  /** The riddle after a command that stored a change, for each follower as its user sees it. */
  readonly changed?: RiddleRow;
  /** The riddle to push as new or ended; a retry names it again in case its first push failed. */
  readonly push?: { readonly riddle: RiddleRow; readonly kind: "sent" | "ended" };
  /** The room's decision for a stored change: the journal entry and coins of an end. */
  readonly decision?: RoomDecision;
}

const decodeEntryId = Schema.decodeSync(CoinEntryId);

/** Runs draw-guess commands against one room: load, decide, commit through the room. */
export class RiddleRoom extends Context.Service<RiddleRoom>()(
  "@billet/backend-pair-room/RiddleRoom",
  {
    make: Effect.gen(function* () {
      const store = yield* RiddleStore;
      const room = yield* RoomStore;
      const service = yield* RoomService;
      // Two commands at once each decide from the one before, so a riddle ends and pays once.
      const lock = yield* Semaphore.make(1);

      const refused = (reason: RiddleRefusal): RiddleOutcome => ({
        result: RiddleResult.cases.Refused.make({ reason }),
      });

      const listed = (by: UserId) =>
        Effect.gen(function* () {
          const { series, best } = yield* store.series;
          const view = (rows: ReadonlyArray<RiddleRow>) => rows.map((row) => riddleView(row, by));
          return RiddleResult.cases.Listed.make({
            view: {
              open: view(yield* store.open),
              ended: view(yield* store.ended(endedRiddleLimit)),
              series,
              best,
            },
          });
        });

      const changed = (row: RiddleRow, by: UserId, right?: boolean) =>
        RiddleResult.cases.Changed.make({
          riddle: riddleView(row, by),
          ...(right === undefined ? {} : { right }),
        });

      /** A send pushes the riddle to its guesser; a round's end, to its drawer. */
      const pushOf = (command: RiddleCommand["_tag"], riddle: RiddleRow, right?: boolean) =>
        command === "Send"
          ? { push: { riddle, kind: "sent" as const } }
          : right === true || command === "GiveUp"
            ? { push: { riddle, kind: "ended" as const } }
            : {};

      const idHeld = (id: RiddleId) =>
        Effect.gen(function* () {
          if (Option.isSome(yield* room.catEntryById(id))) return true;
          return Option.isSome(yield* room.coinEntryById(decodeEntryId(`earn:${id}`)));
        });

      const apply = (by: UserId, command: RiddleCommand["_tag"], decision: RiddleDecision) =>
        Effect.gen(function* () {
          switch (decision._tag) {
            case "Refused":
              return refused(decision.reason);
            case "Repeated": {
              const { riddle, right } = decision;
              return { result: changed(riddle, by, right), ...pushOf(command, riddle, right) };
            }
            case "Stored": {
              const { write, right } = decision;
              // An entry recorded under the riddle's id after it was sent would make the round's own
              // entry collide and the riddle stay open; it ends without journal or coins instead.
              const reward =
                decision.reward !== undefined && (yield* idHeld(write.riddle.id))
                  ? undefined
                  : decision.reward;
              const stored = yield* service.dispatch({
                _tag: "SaveRiddle",
                by,
                at: yield* Clock.currentTimeMillis,
                write,
                ...(reward === undefined ? {} : { reward }),
              });
              if (stored._tag === "Rejected") return refused("NotOpen");
              const { riddle } = write;
              return {
                result: changed(riddle, by, right),
                changed: riddle,
                ...pushOf(command, riddle, right),
                decision: stored,
              } satisfies RiddleOutcome;
            }
          }
        });

      const playing = (id: RiddleId, decide: (row: RiddleRow) => Effect.Effect<RiddleDecision>) =>
        Effect.gen(function* () {
          const row = yield* store.byId(id);
          return Option.isNone(row)
            ? ({ _tag: "Refused", reason: "NotFound" } as const)
            : yield* decide(row.value);
        });

      const decisionFor = (by: UserId, command: Exclude<RiddleCommand, { _tag: "View" }>) =>
        Effect.gen(function* () {
          const at = yield* Clock.currentTimeMillis;
          switch (command._tag) {
            case "Send": {
              const existing = Option.getOrUndefined(yield* store.byId(command.id));
              // A riddle's end journals and pays under its own id, so a new one may not take an id
              // a note or a care entry already holds.
              if (existing === undefined && (yield* idHeld(command.id))) {
                return { _tag: "Refused", reason: "IdTaken" } as const;
              }
              const { _tag, ...request } = command;
              return decideSend(existing, yield* store.open, by, request, at);
            }
            case "Guess":
              return yield* playing(command.riddle, (row) =>
                Effect.gen(function* () {
                  const earlier = yield* store.guess(row.id, command.key);
                  const series = yield* store.series;
                  return decideGuess(row, Option.getOrUndefined(earlier), series, by, command, at);
                }),
              );
            case "Hint":
              return yield* playing(command.riddle, (row) => Effect.succeed(decideHint(row, by)));
            case "GiveUp":
              return yield* playing(command.riddle, (row) =>
                store.series.pipe(Effect.map((series) => decideGiveUp(row, series, by, at))),
              );
          }
        });

      const run = (by: UserId, command: RiddleCommand): Effect.Effect<RiddleOutcome> =>
        Effect.gen(function* () {
          const state = yield* room.load;
          if (state._tag !== "Active" || !state.members.some((member) => member.user === by)) {
            return refused("NotOpen");
          }
          if (command._tag === "View") return { result: yield* listed(by) };
          return yield* apply(by, command._tag, yield* decisionFor(by, command));
        }).pipe(lock.withPermits(1));

      return { run, byId: store.byId, forget: store.forget.pipe(lock.withPermits(1)) };
    }),
  },
) {
  static readonly layer = Layer.effect(RiddleRoom, RiddleRoom.make);
}
