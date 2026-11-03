import { Clock, Context, Effect, Layer, Option, Semaphore } from "effect";
import type { EpochMillis, NoteId, UserId } from "@billet/contracts-domain/ids";
import type { Note } from "@billet/contracts-domain/note";
import type { SendNoteRequest } from "@billet/contracts-http-api/note";
import { decide } from "./decide.ts";
import { NoteIdSource } from "./note-id-source.ts";
import type { RoomCommand } from "./room-command.ts";
import { RoomDecision, RoomOutput } from "./room-decision.ts";
import { RoomStore, type AppendedNote } from "./room-store.ts";

const notesIn = (outputs: ReadonlyArray<RoomOutput>): ReadonlyArray<AppendedNote> =>
  outputs.flatMap((output) => {
    switch (output._tag) {
      case "NoteAppended":
        return [{ entry: output.entry, key: output.key }];
      case "NoteRepeated":
      case "RoomOpened":
      case "PresenceChanged":
        return [];
    }
  });

const stamped = (
  request: SendNoteRequest,
  server: { readonly id: NoteId; readonly author: UserId; readonly sentAt: EpochMillis },
): Note => {
  switch (request._tag) {
    case "Drawing":
      return { _tag: "Drawing", compact: request.compact, image: request.image, ...server };
    case "Photo":
      return { _tag: "Photo", image: request.image, ...server };
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
              yield* store.commit(decision.state, notesIn(decision.outputs));
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
      const forgetAuthor = (author: UserId) => store.forgetAuthor(author).pipe(lock.withPermits(1));

      return {
        dispatch,
        sendNote,
        forgetAuthor,
        state: store.load,
        notesAfter: store.notesAfter,
      };
    }),
  },
) {
  static readonly layer = Layer.effect(RoomService, RoomService.make);
}
