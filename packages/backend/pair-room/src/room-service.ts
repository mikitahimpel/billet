import { Clock, Context, Effect, Layer, Semaphore } from "effect";
import type { EpochMillis, NoteId, UserId } from "@billet/contracts-domain/ids";
import type { Note } from "@billet/contracts-domain/note";
import type { SendNoteRequest } from "@billet/contracts-http-api/note";
import { decide } from "./decide.ts";
import { NoteIdSource } from "./note-id-source.ts";
import type { RoomCommand } from "./room-command.ts";
import { RoomOutput } from "./room-decision.ts";
import type { RoomDecision } from "./room-decision.ts";
import type { SequencedNote } from "./room-state.ts";
import { RoomStore } from "./room-store.ts";

const notesIn = (outputs: ReadonlyArray<RoomOutput>): ReadonlyArray<SequencedNote> =>
  outputs.flatMap((output) => {
    switch (output._tag) {
      case "NoteAppended":
        return [output.entry];
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
      return { ...request, ...server };
    case "Photo":
      return { ...request, ...server };
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

      const dispatch = (command: RoomCommand): Effect.Effect<RoomDecision> =>
        Effect.gen(function* () {
          const decision = decide(yield* store.load, command);
          switch (decision._tag) {
            case "Accepted":
              yield* store.commit(decision.state, notesIn(decision.outputs));
              return decision;
            case "Rejected":
              return decision;
          }
        }).pipe(lock.withPermits(1));

      const sendNote = (author: UserId, request: SendNoteRequest) =>
        Effect.gen(function* () {
          const id = yield* noteIds.next;
          const sentAt = yield* Clock.currentTimeMillis;
          return yield* dispatch({
            _tag: "SendNote",
            note: stamped(request, { id, author, sentAt }),
          });
        });

      return { dispatch, sendNote, state: store.load, notesAfter: store.notesAfter };
    }),
  },
) {
  static readonly layer = Layer.effect(RoomService, RoomService.make);
}
