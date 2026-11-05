import { Effect, Layer, Schema } from "effect";
import { NotesUnavailable } from "@billet/backend-notes/notes-error";
import { PairRooms } from "@billet/backend-notes/pair-rooms";
import { InkId } from "@billet/contracts-domain/inks";
import { GiftsResult } from "@billet/backend-pair-room/gifts";
import { RoomDecision } from "@billet/backend-pair-room/room-decision";
import { SequencedNote } from "@billet/backend-pair-room/room-state";
import { CatEntry } from "@billet/contracts-domain/cat";
import { ActivityResponse } from "@billet/contracts-http-api/activity";
import { CatResponse } from "@billet/contracts-http-api/cat";
import { CoinsResponse } from "@billet/contracts-http-api/coins";
import { ShopResponse } from "@billet/contracts-http-api/shop";
import { NoteReaction } from "@billet/contracts-domain/reaction";
import { MoodCheckIn } from "@billet/contracts-domain/mood";
import type { PairRoom } from "./pair-room-durable-object.ts";
import { spanMethods } from "@billet/backend-observability/span-methods";

const decodeDecision = Schema.decodeUnknownEffect(RoomDecision);
const decodeNotes = Schema.decodeUnknownEffect(Schema.Array(SequencedNote));
const decodeCat = Schema.decodeUnknownEffect(Schema.NullOr(CatResponse));
const decodeReactions = Schema.decodeUnknownEffect(Schema.Array(NoteReaction));
const decodeJournal = Schema.decodeUnknownEffect(Schema.Array(CatEntry));
const decodeActivity = Schema.decodeUnknownEffect(ActivityResponse);
const decodeUnread = Schema.decodeUnknownEffect(Schema.Int);
const decodeInks = Schema.decodeUnknownEffect(Schema.Array(InkId));
const decodeCoins = Schema.decodeUnknownEffect(Schema.NullOr(CoinsResponse));
const decodeShop = Schema.decodeUnknownEffect(Schema.NullOr(ShopResponse));
const decodeMoods = Schema.decodeUnknownEffect(Schema.Array(MoodCheckIn));
const decodeGifts = Schema.decodeUnknownEffect(GiftsResult);

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
        open: (pairId, members, joined) =>
          callRoom(() => rooms.getByName(pairId).open(pairId, members, joined), decodeDecision),
        sendNote: (pairId, author, request) =>
          callRoom(() => rooms.getByName(pairId).sendNote(author, request), decodeDecision),
        inks: (pairId) => callRoom(() => rooms.getByName(pairId).inks(), decodeInks),
        grantInks: (pairId, inks) =>
          callRoom(() => rooms.getByName(pairId).grantInks(inks), decodeDecision),
        coins: (pairId, after, limit) =>
          callRoom(() => rooms.getByName(pairId).coins(after, limit), decodeCoins),
        buy: (pairId, by, id, ink) =>
          callRoom(() => rooms.getByName(pairId).buy(by, id, ink), decodeDecision),
        shop: (pairId) => callRoom(() => rooms.getByName(pairId).shop(), decodeShop),
        order: (pairId, by, id, offer, utcOffsetSeconds) =>
          callRoom(
            () => rooms.getByName(pairId).order(by, id, offer, utcOffsetSeconds),
            decodeDecision,
          ),
        openGift: (pairId, by, utcOffsetSeconds) =>
          callRoom(() => rooms.getByName(pairId).openGift(by, utcOffsetSeconds), decodeDecision),
        claimBonus: (pairId, by, collection) =>
          callRoom(() => rooms.getByName(pairId).claimBonus(by, collection), decodeDecision),
        earn: (pairId, by, event, utcOffsetSeconds) =>
          callRoom(() => rooms.getByName(pairId).earn(by, event, utcOffsetSeconds), decodeDecision),
        creditPurchase: (pairId, credit) =>
          callRoom(() => rooms.getByName(pairId).creditPurchase(credit), decodeDecision),
        setWish: (pairId, by, item, wished) =>
          callRoom(() => rooms.getByName(pairId).setWish(by, item, wished), decodeDecision),
        notesAfter: (pairId, afterSeq, limit) =>
          callRoom(() => rooms.getByName(pairId).notes(afterSeq, limit), decodeNotes),
        forgetMember: (pairId, user) =>
          callRoom(() => rooms.getByName(pairId).forgetMember(user), decodeNotes),
        endSessions: (pairId) =>
          callRoom(
            () => rooms.getByName(pairId).endSessions(),
            () => Effect.void,
          ),
        saveCat: (pairId, user, request, natureSeed) =>
          callRoom(
            () => rooms.getByName(pairId).saveCat(user, request, natureSeed),
            decodeDecision,
          ),
        recordCatEvent: (pairId, user, request) =>
          callRoom(() => rooms.getByName(pairId).recordCatEvent(user, request), decodeDecision),
        cat: (pairId) => callRoom(() => rooms.getByName(pairId).cat(), decodeCat),
        catJournal: (pairId, afterSeq, limit) =>
          callRoom(() => rooms.getByName(pairId).catJournal(afterSeq, limit), decodeJournal),
        activity: (pairId, caller, before, limit) =>
          callRoom(() => rooms.getByName(pairId).activity(caller, before, limit), decodeActivity),
        react: (pairId, by, request) =>
          callRoom(() => rooms.getByName(pairId).react(by, request), decodeDecision),
        reactions: (pairId, afterRev, limit) =>
          callRoom(() => rooms.getByName(pairId).reactions(afterRev, limit), decodeReactions),
        setMood: (pairId, by, request) =>
          callRoom(() => rooms.getByName(pairId).setMood(by, request), decodeDecision),
        moods: (pairId) => callRoom(() => rooms.getByName(pairId).moods(), decodeMoods),
        gifts: (pairId, by, command) =>
          callRoom(() => rooms.getByName(pairId).gifts(by, command), decodeGifts),
        markActivityRead: (pairId, user, upTo) =>
          callRoom(() => rooms.getByName(pairId).markActivityRead(user, upTo), decodeUnread),
      }),
    ),
  );
