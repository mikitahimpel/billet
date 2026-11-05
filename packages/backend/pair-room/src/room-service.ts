import { Clock, Context, Effect, Layer, Option, Schema, Semaphore } from "effect";
import type { CatEntry, NatureSeed } from "@billet/contracts-domain/cat";
import { type CoinEntry, CoinEntryId } from "@billet/contracts-domain/coins";
import type { InkId } from "@billet/contracts-domain/inks";
import type { EpochMillis, IdempotencyKey, NoteId, UserId } from "@billet/contracts-domain/ids";
import type {
  CatResponse,
  RecordCatEventRequest,
  SaveCatRequest,
} from "@billet/contracts-http-api/cat";
import type { Note, PaperColor } from "@billet/contracts-domain/note";
import type { SendNoteRequest } from "@billet/contracts-http-api/note";
import type { ReactRequest } from "@billet/contracts-http-api/reaction";
import type { NoteReaction } from "@billet/contracts-domain/reaction";
import type { ActivityCursor } from "@billet/contracts-domain/activity";
import type { ActivityResponse } from "@billet/contracts-http-api/activity";
import { activityOf, cursorOf, itemFor } from "./activity.ts";
import { catNeeds, lifeHorizonMillis } from "./cat-life.ts";
import { newTemper } from "./cat-temper.ts";
import { decide } from "./decide.ts";
import { NoteIdSource } from "./note-id-source.ts";
import type { RoomCommand } from "./room-command.ts";
import { RoomDecision, RoomOutput, RoomRejection } from "./room-decision.ts";
import { RoomStore, type AppendedNote } from "./room-store.ts";

const notesIn = (outputs: ReadonlyArray<RoomOutput>): ReadonlyArray<AppendedNote> =>
  outputs.flatMap((output) => {
    switch (output._tag) {
      case "NoteAppended":
        return [{ entry: output.entry, key: output.key }];
      case "NoteRepeated":
      case "RoomOpened":
      case "PresenceChanged":
      case "CatSaved":
      case "CatEntryAppended":
      case "CatEntryRepeated":
      case "InksGranted":
      case "CoinsEntered":
      case "CoinsRepeated":
      case "ReactionSet":
      case "ReactionRepeated":
        return [];
    }
  });

const reactionsIn = (outputs: ReadonlyArray<RoomOutput>): ReadonlyArray<NoteReaction> =>
  outputs.flatMap((output) => (output._tag === "ReactionSet" ? [output.reaction] : []));

const coinsIn = (outputs: ReadonlyArray<RoomOutput>): ReadonlyArray<CoinEntry> =>
  outputs.flatMap((output) => (output._tag === "CoinsEntered" ? [output.entry] : []));

const decodeEntryId = Schema.decodeSync(CoinEntryId);

const catEntriesIn = (outputs: ReadonlyArray<RoomOutput>): ReadonlyArray<CatEntry> =>
  outputs.flatMap((output) => (output._tag === "CatEntryAppended" ? [output.entry] : []));

// `paper` is an optional key: a note without one carries no `paper` at all, never `undefined`.
const paperOf = (request: { readonly paper?: PaperColor }) =>
  request.paper === undefined ? {} : { paper: request.paper };

const stamped = (
  request: SendNoteRequest,
  server: { readonly id: NoteId; readonly author: UserId; readonly sentAt: EpochMillis },
): Note => {
  switch (request._tag) {
    case "Drawing":
      return {
        _tag: "Drawing",
        compact: request.compact,
        image: request.image,
        ...paperOf(request),
        ...server,
      };
    case "Photo":
      return {
        _tag: "Photo",
        image: request.image,
        width: request.width,
        height: request.height,
        preview: request.preview,
        ...(request.caption === undefined ? {} : { caption: request.caption }),
        ...server,
      };
    case "Text":
      return { _tag: "Text", text: request.text, ...paperOf(request), ink: request.ink, ...server };
  }
};

/** Runs commands against one room: load, decide, commit. */
export class RoomService extends Context.Service<RoomService>()(
  "@billet/backend-pair-room/RoomService",
  {
    make: Effect.gen(function* () {
      const store = yield* RoomStore;
      const noteIds = yield* NoteIdSource;
      // A Durable Object only blocks new events while it waits on storage, and a fiber can yield
      // between load and commit. Without this lock two commands could decide from the same state.
      const lock = yield* Semaphore.make(1);

      const decideAndCommit = (command: RoomCommand): Effect.Effect<RoomDecision> =>
        Effect.gen(function* () {
          const decision = decide(yield* store.load, command);
          switch (decision._tag) {
            case "Accepted":
              yield* store.commit(
                decision.state,
                notesIn(decision.outputs),
                catEntriesIn(decision.outputs),
                activityOf(decision.outputs, yield* Clock.currentTimeMillis),
                coinsIn(decision.outputs),
                reactionsIn(decision.outputs),
              );
              return decision;
            case "Rejected":
              return decision;
          }
        });

      const dispatch = (command: RoomCommand) => decideAndCommit(command).pipe(lock.withPermits(1));

      // The id and the time are taken inside the lock, so `sentAt` follows the order of `seq`. A key
      // the author already used answers with that note, also inside the lock, so two sends of one
      // key at once store one note.
      const sendNote = (author: UserId, request: SendNoteRequest) =>
        Effect.gen(function* () {
          const state = yield* store.load;
          if (state._tag === "Active") {
            const earlier = yield* store.noteByKey(author, request.key);
            if (Option.isSome(earlier)) {
              return RoomDecision.cases.Accepted.make({
                state,
                outputs: [RoomOutput.cases.NoteRepeated.make({ entry: earlier.value })],
              });
            }
          }
          const id = yield* noteIds.next;
          const sentAt = yield* Clock.currentTimeMillis;
          return yield* decideAndCommit({
            _tag: "SendNote",
            note: stamped(request, { id, author, sentAt }),
            key: request.key,
          });
        }).pipe(lock.withPermits(1));

      // Under the lock, so a note the author is sending at the same moment is not left behind.
      // The pair is ending, so the cat goes with it.
      const forgetAuthor = (author: UserId) =>
        store.forgetCat.pipe(
          Effect.andThen(store.forgetActivity),
          Effect.andThen(store.forgetReactions),
          Effect.andThen(store.forgetAuthor(author)),
          lock.withPermits(1),
        );

      const unread = (user: UserId) =>
        store
          .readMark(user)
          .pipe(Effect.flatMap((mark) => store.unreadCount(user, Option.getOrUndefined(mark))));

      /** One page of the Inbox as `caller` sees it, newest first. */
      const activityPage = (caller: UserId, before: ActivityCursor | undefined, limit: number) =>
        Effect.gen(function* () {
          // One more than asked tells whether there is a page after this one.
          const rows = yield* store.activityBefore(before, limit + 1);
          const page = rows.slice(0, limit);
          const last = page.at(-1);
          // The first page starts at the head; a later one asks for it, one row.
          const [head] = before === undefined ? rows : yield* store.activityBefore(undefined, 1);
          const response: ActivityResponse = {
            items: page.map((row) => itemFor(row, caller)),
            ...(rows.length > limit && last !== undefined ? { next: cursorOf(last) } : {}),
            ...(head === undefined ? {} : { head: cursorOf(head) }),
            unread: yield* unread(caller),
          };
          return response;
        });

      // Under the lock, so two devices reading at once leave the later mark.
      const markActivityRead = (user: UserId, upTo: ActivityCursor) =>
        Effect.gen(function* () {
          const mark = yield* store.readMark(user);
          if (Option.isNone(mark) || upTo > mark.value) yield* store.saveReadMark(user, upTo);
          return yield* unread(user);
        }).pipe(lock.withPermits(1));

      // The time is taken inside the lock, so a cat's birth follows the order of the room.
      const saveCat = (user: UserId, request: SaveCatRequest, natureSeed: NatureSeed) =>
        Effect.gen(function* () {
          const at = yield* Clock.currentTimeMillis;
          return yield* decideAndCommit({ _tag: "SaveCat", user, natureSeed, at, ...request });
        }).pipe(lock.withPermits(1));

      // Like a note: the time inside the lock, so `at` follows `seq`, and a repeated `id` answers
      // with the entry already stored.
      const recordCatEvent = (by: UserId, request: RecordCatEventRequest) =>
        Effect.gen(function* () {
          const state = yield* store.load;
          if (state._tag === "Active") {
            const earlier = yield* store.catEntryById(request.id);
            if (Option.isSome(earlier)) {
              return earlier.value.by === by
                ? RoomDecision.cases.Accepted.make({
                    state,
                    outputs: [RoomOutput.cases.CatEntryRepeated.make({ entry: earlier.value })],
                  })
                : RoomDecision.cases.Rejected.make({
                    rejection: RoomRejection.cases.CatEntryIdTaken.make({}),
                  });
            }
          }
          const at = yield* Clock.currentTimeMillis;
          return yield* decideAndCommit({ _tag: "RecordCatEvent", by, at, ...request });
        }).pipe(lock.withPermits(1));

      // The note and `by`'s reaction to it are read inside the lock, so two changes at once each
      // decide from the one before.
      const react = (by: UserId, request: ReactRequest) =>
        Effect.gen(function* () {
          const stored = yield* store.noteById(request.note);
          if (Option.isNone(stored)) {
            return RoomDecision.cases.Rejected.make({
              rejection: RoomRejection.cases.NoteNotFound.make({}),
            });
          }
          const current = yield* store.reactionOf(request.note, by);
          const at = yield* Clock.currentTimeMillis;
          return yield* decideAndCommit({
            _tag: "React",
            by,
            note: stored.value.note,
            ...(Option.isSome(current) ? { current: current.value } : {}),
            ...(request.reaction === undefined ? {} : { reaction: request.reaction }),
            at,
          });
        }).pipe(lock.withPermits(1));

      // Like a cat entry: a repeated `id` answers with the spend already stored, charging nothing.
      const buy = (by: UserId, id: IdempotencyKey, ink: InkId) =>
        Effect.gen(function* () {
          const state = yield* store.load;
          if (state._tag === "Active") {
            const earlier = yield* store.coinEntryById(decodeEntryId(`spend:${id}`));
            if (Option.isSome(earlier)) {
              return RoomDecision.cases.Accepted.make({
                state,
                outputs: [RoomOutput.cases.CoinsRepeated.make({ entry: earlier.value })],
              });
            }
          }
          const at = yield* Clock.currentTimeMillis;
          return yield* decideAndCommit({ _tag: "Buy", id, by, ink, at });
        }).pipe(lock.withPermits(1));

      /**
       * The cat at the room's clock now, or null while the room is not open. Before adoption, a
       * cat born now, so the answer has one shape.
       */
      const catView: Effect.Effect<CatResponse | null> = Effect.gen(function* () {
        const now = yield* Clock.currentTimeMillis;
        const state = yield* store.load;
        if (state._tag !== "Active") return null;
        const partners = [state.members[0].user, state.members[1].user] as const;
        if (state.cat === undefined) {
          return {
            temper: newTemper,
            needs: catNeeds([], now, { partners, utcOffsetSeconds: 0, bornAt: now }),
            lastSeq: 0,
          };
        }
        const { profile, temper, lastSeq } = state.cat;
        const entries = yield* store.catEntriesSince(Math.max(0, now - lifeHorizonMillis));
        const needs = catNeeds(entries, now, {
          partners,
          utcOffsetSeconds: profile.utcOffsetSeconds,
          bornAt: profile.bornAt,
        });
        return { cat: profile, temper, needs, lastSeq };
      });

      return {
        dispatch,
        sendNote,
        forgetAuthor,
        saveCat,
        recordCatEvent,
        react,
        buy,
        catView,
        activityPage,
        markActivityRead,
        unread,
        state: store.load,
        notesAfter: store.notesAfter,
        noteById: store.noteById,
        catEntriesAfter: store.catEntriesAfter,
        reactionsAfter: store.reactionsAfter,
        coinEntriesAfter: store.coinEntriesAfter,
      };
    }),
  },
) {
  static readonly layer = Layer.effect(RoomService, RoomService.make);
}
