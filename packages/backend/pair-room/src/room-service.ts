import { Clock, Context, Effect, Layer, Option, Semaphore } from "effect";
import type { CatEntry, NatureSeed } from "@billet/contracts-domain/cat";
import type { EpochMillis, NoteId, UserId } from "@billet/contracts-domain/ids";
import type {
  CatResponse,
  RecordCatEventRequest,
  SaveCatRequest,
} from "@billet/contracts-http-api/cat";
import type { Note, PaperColor } from "@billet/contracts-domain/note";
import type { SendNoteRequest } from "@billet/contracts-http-api/note";
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
        return [];
    }
  });

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
      return { _tag: "Text", text: request.text, ...paperOf(request), ...server };
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
        store.forgetCat.pipe(Effect.andThen(store.forgetAuthor(author)), lock.withPermits(1));

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
        catView,
        state: store.load,
        notesAfter: store.notesAfter,
        catEntriesAfter: store.catEntriesAfter,
      };
    }),
  },
) {
  static readonly layer = Layer.effect(RoomService, RoomService.make);
}
