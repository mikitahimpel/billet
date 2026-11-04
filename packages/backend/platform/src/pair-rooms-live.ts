import { Effect, Layer, Schema } from "effect";
import { NotesUnavailable } from "@billet/backend-notes/notes-error";
import { PairRooms } from "@billet/backend-notes/pair-rooms";
import { RoomDecision } from "@billet/backend-pair-room/room-decision";
import { SequencedNote } from "@billet/backend-pair-room/room-state";
import type { PairRoom } from "./pair-room-durable-object.ts";
import { spanMethods } from "@billet/backend-observability/span-methods";

const decodeDecision = Schema.decodeUnknownEffect(RoomDecision);
const decodeNotes = Schema.decodeUnknownEffect(Schema.Array(SequencedNote));

const unavailable = (cause: unknown) => new NotesUnavailable({ reason: "room-unavailable", cause });

/** RPC erases tuples and brands from the stub's types, so a reply is decoded as it comes back. */
const callRoom = <A, E>(
  call: () => Promise<unknown>,
  decode: (reply: unknown) => Effect.Effect<A, E>,
) =>
  Effect.tryPromise({ try: call, catch: unavailable }).pipe(
    Effect.flatMap(decode),
    Effect.mapError(unavailable),
  );

/** `PairRooms` on the Durable Object namespace: a couple's object is named after its pair id. */
export const PairRoomsLive = (rooms: DurableObjectNamespace<PairRoom>): Layer.Layer<PairRooms> =>
  Layer.succeed(
    PairRooms,
    PairRooms.of(
      spanMethods("PairRooms", {
        open: (pairId, members) =>
          callRoom(() => rooms.getByName(pairId).open(pairId, members), decodeDecision),
        sendNote: (pairId, author, request) =>
          callRoom(() => rooms.getByName(pairId).sendNote(author, request), decodeDecision),
        notesAfter: (pairId, afterSeq, limit) =>
          callRoom(() => rooms.getByName(pairId).notes(afterSeq, limit), decodeNotes),
        forgetMember: (pairId, user) =>
          callRoom(() => rooms.getByName(pairId).forgetMember(user), decodeNotes),
      }),
    ),
  );
