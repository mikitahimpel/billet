import { Clock, Context, Effect, Layer, Option, Schema, Semaphore } from "effect";
import type { CatEntry, NatureSeed } from "@billet/contracts-domain/cat";
import {
  type CoinEntry,
  CoinEntryId,
  EarnRef,
  type EarnEvent,
  localDayOf,
  rewardForEarn,
} from "@billet/contracts-domain/coins";
import type { ListCommand } from "@billet/contracts-domain/list";
import type { InkId } from "@billet/contracts-domain/inks";
import type { CollectionId, RoomItemId, ShopOffer } from "@billet/contracts-domain/shop";
import type { PriceTerms } from "@billet/contracts-domain/shop-catalog";
import type { EpochMillis, IdempotencyKey, NoteId, UserId } from "@billet/contracts-domain/ids";
import type {
  CatResponse,
  RecordCatEventRequest,
  SaveCatRequest,
} from "@billet/contracts-http-api/cat";
import type { Note, PaperColor } from "@billet/contracts-domain/note";
import type { SendNoteRequest } from "@billet/contracts-http-api/note";
import type { ReactRequest } from "@billet/contracts-http-api/reaction";
import type { SetMoodRequest } from "@billet/contracts-http-api/mood";
import type { MoodCheckIn } from "@billet/contracts-domain/mood";
import type { NoteReaction } from "@billet/contracts-domain/reaction";
import type { ActivityCursor } from "@billet/contracts-domain/activity";
import type { ActivityResponse } from "@billet/contracts-http-api/activity";
import { activityOf, cursorOf, itemFor } from "./activity.ts";
import { catNeeds, lifeHorizonMillis } from "./cat-life.ts";
import { newTemper } from "./cat-temper.ts";
import { decide, isMember } from "./decide.ts";
import { listRefusalOf, ListsResult } from "./lists.ts";
import { NoteIdSource } from "./note-id-source.ts";
import type { RiddleWrite } from "./riddle-rules.ts";
import type { RoomCommand } from "./room-command.ts";
import { RoomDecision, RoomOutput, RoomRejection } from "./room-decision.ts";
import type { RoomState } from "./room-state.ts";
import { RoomStore, type AppendedNote, type ListWrite } from "./room-store.ts";

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
      case "ItemsGranted":
      case "WishlistChanged":
      case "CoinsEntered":
      case "CoinsRepeated":
      case "ReactionSet":
      case "ReactionRepeated":
      case "Purchased":
      case "GiftOpened":
      case "BonusPaid":
      case "ListSaved":
      case "ListDeleted":
      case "ListItemAdded":
      case "MoodSet":
      case "RiddleSaved":
        return [];
    }
  });

const listWritesIn = (outputs: ReadonlyArray<RoomOutput>): ReadonlyArray<ListWrite> =>
  outputs.flatMap((output): ReadonlyArray<ListWrite> =>
    output._tag === "ListSaved"
      ? [{ _tag: "Put", list: output.list, key: output.key, at: output.at }]
      : output._tag === "ListDeleted"
        ? [{ _tag: "Drop", list: output.list, key: output.key, at: output.at }]
        : [],
  );

const reactionsIn = (outputs: ReadonlyArray<RoomOutput>): ReadonlyArray<NoteReaction> =>
  outputs.flatMap((output) => (output._tag === "ReactionSet" ? [output.reaction] : []));

const riddlesIn = (outputs: ReadonlyArray<RoomOutput>): ReadonlyArray<RiddleWrite> =>
  outputs.flatMap((output) => (output._tag === "RiddleSaved" ? [output.write] : []));

const coinsIn = (outputs: ReadonlyArray<RoomOutput>): ReadonlyArray<CoinEntry> =>
  outputs.flatMap((output) => (output._tag === "CoinsEntered" ? [output.entry] : []));

const decodeEntryId = Schema.decodeSync(CoinEntryId);
const decodeEarnRef = Schema.decodeSync(EarnRef);

/**
 * A change to the coins a pair bought, under the payments ledger's entry id. A credit names its
 * coins. A reversal (a refund, or a refund Apple reversed) takes back or gives back what the entry
 * it `reverses` moved, so a restore returns only what its refund took; nothing when the room lacks
 * that entry.
 */
export type PurchaseCredit =
  | {
      readonly kind: "buy";
      readonly id: CoinEntryId;
      readonly ref: string;
      readonly coins: number;
    }
  | {
      readonly kind: "buy" | "refund";
      readonly id: CoinEntryId;
      readonly ref: string;
      readonly reverses: CoinEntryId;
    };

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

      const commitOnly = (command: RoomCommand): Effect.Effect<RoomDecision> =>
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
                listWritesIn(decision.outputs),
                riddlesIn(decision.outputs),
              );
              return decision;
            case "Rejected":
              return decision;
          }
        });

      // Every open room gets its welcome coins once: a new one right after it opens, one opened
      // before they existed on its next command or read. Callers hold the lock.
      const welcome = Effect.gen(function* () {
        const state = yield* store.load;
        if (state._tag !== "Active" || state.welcomed) return;
        yield* commitOnly({ _tag: "Welcome", at: yield* Clock.currentTimeMillis });
      });

      const activeState = store.load.pipe(
        Effect.flatMap((state) =>
          state._tag === "Active" ? Effect.succeed(state) : Effect.die("the room closed"),
        ),
      );

      const decideAndCommit = (command: RoomCommand): Effect.Effect<RoomDecision> =>
        Effect.gen(function* () {
          yield* welcome;
          const decision = yield* commitOnly(command);
          if (decision._tag === "Accepted" && !decision.state.welcomed) {
            yield* welcome;
            return RoomDecision.cases.Accepted.make({ ...decision, state: yield* activeState });
          }
          return decision;
        });

      /** The room's state, after any welcome coins it is owed. */
      const settled = welcome.pipe(Effect.andThen(store.load), lock.withPermits(1));

      /** The offset a day is counted in: the caller's, else the cat's, else UTC. */
      const offsetFor = (state: RoomState, utcOffsetSeconds: number | undefined): number =>
        utcOffsetSeconds ??
        (state._tag === "Active" && state.cat !== undefined
          ? state.cat.profile.utcOffsetSeconds
          : 0);

      /** An answer that repeats an entry already stored, so nothing is charged or paid again. */
      const repeated = (state: RoomState, id: CoinEntryId) =>
        Effect.gen(function* () {
          if (state._tag !== "Active") return undefined;
          const earlier = yield* store.coinEntryById(id);
          return Option.isSome(earlier)
            ? RoomDecision.cases.Accepted.make({
                state,
                outputs: [RoomOutput.cases.CoinsRepeated.make({ entry: earlier.value })],
              })
            : undefined;
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
          Effect.andThen(store.forgetMoods),
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
      const spendOnce = (id: IdempotencyKey, command: (at: EpochMillis) => RoomCommand) =>
        Effect.gen(function* () {
          const earlier = yield* repeated(yield* store.load, decodeEntryId(`spend:${id}`));
          if (earlier !== undefined) return earlier;
          return yield* decideAndCommit(command(yield* Clock.currentTimeMillis));
        }).pipe(lock.withPermits(1));

      const buy = (by: UserId, id: IdempotencyKey, ink: InkId, terms?: PriceTerms) =>
        spendOnce(id, (at) => ({
          _tag: "Buy",
          id,
          by,
          ink,
          at,
          ...(terms === undefined ? {} : { terms }),
        }));

      const order = (
        by: UserId,
        id: IdempotencyKey,
        offer: ShopOffer,
        utcOffsetSeconds?: number,
        terms?: PriceTerms,
      ) =>
        spendOnce(id, (at) => ({
          _tag: "Order",
          id,
          by,
          offer,
          at,
          ...(utcOffsetSeconds === undefined ? {} : { utcOffsetSeconds }),
          ...(terms === undefined ? {} : { terms }),
        }));

      // The day's gift is the pair's, so the partner opening it again answers with the first.
      const openGift = (by: UserId, utcOffsetSeconds: number | undefined) =>
        Effect.gen(function* () {
          const state = yield* store.load;
          const at = yield* Clock.currentTimeMillis;
          const offset = offsetFor(state, utcOffsetSeconds);
          const earlier = yield* repeated(state, decodeEntryId(`gift:${localDayOf(at, offset)}`));
          if (earlier !== undefined) return earlier;
          return yield* decideAndCommit({ _tag: "OpenGift", by, at, utcOffsetSeconds: offset });
        }).pipe(lock.withPermits(1));

      // Paid once ever: asking again answers with the bonus already paid.
      const claimBonus = (by: UserId, collection: CollectionId) =>
        Effect.gen(function* () {
          const earlier = yield* repeated(yield* store.load, decodeEntryId(`bonus:${collection}`));
          if (earlier !== undefined) return earlier;
          const at = yield* Clock.currentTimeMillis;
          return yield* decideAndCommit({ _tag: "ClaimBonus", by, at, collection });
        }).pipe(lock.withPermits(1));

      // Once per ref: the same wish, idea or item again answers with the coins it already earned.
      const earn = (by: UserId, event: EarnEvent, utcOffsetSeconds: number | undefined) =>
        Effect.gen(function* () {
          const state = yield* store.load;
          const earlier = yield* repeated(state, rewardForEarn(event).id);
          if (earlier !== undefined) return earlier;
          const at = yield* Clock.currentTimeMillis;
          return yield* decideAndCommit({
            _tag: "Earn",
            by,
            at,
            utcOffsetSeconds: offsetFor(state, utcOffsetSeconds),
            event,
          });
        }).pipe(lock.withPermits(1));

      // Once per entry id: the payments side calls again for a retry or a duplicate transaction.
      const creditPurchase = (credit: PurchaseCredit) =>
        Effect.gen(function* () {
          const earlier = yield* repeated(yield* store.load, credit.id);
          if (earlier !== undefined) return earlier;
          const coins =
            "coins" in credit
              ? credit.coins
              : Option.match(yield* store.coinEntryById(credit.reverses), {
                  onNone: () => 0,
                  onSome: (entry) => Math.abs(entry.amount),
                });
          return yield* decideAndCommit({
            _tag: "CreditPurchase",
            id: credit.id,
            kind: credit.kind,
            coins,
            ref: credit.ref,
            at: yield* Clock.currentTimeMillis,
          });
        }).pipe(lock.withPermits(1));

      // The list and whether its item was paid are read inside the lock, like a reaction's note. A
      // key the room already holds answers with nothing changed.
      const changeList = (by: UserId, change: ListCommand, utcOffsetSeconds: number | undefined) =>
        Effect.gen(function* () {
          const state = yield* store.load;
          if (state._tag === "Active" && (yield* store.listKeyUsed(change.key))) {
            return RoomDecision.cases.Accepted.make({ state, outputs: [] });
          }
          const list = Option.getOrUndefined(yield* store.listById(change.list));
          const paid =
            change._tag === "TickItem" &&
            Option.isSome(
              yield* store.coinEntryById(
                rewardForEarn({ _tag: "ListTicked", item: decodeEarnRef(change.item) }).id,
              ),
            );
          return yield* decideAndCommit({
            _tag: "ChangeList",
            by,
            at: yield* Clock.currentTimeMillis,
            utcOffsetSeconds: offsetFor(state, utcOffsetSeconds),
            change,
            ...(list === undefined ? {} : { list }),
            paid,
          });
        }).pipe(lock.withPermits(1));

      // Under the lock, like a note: a change at the same moment is not left out of the view.
      const forgetLists = store.forgetLists.pipe(lock.withPermits(1));

      /**
       * The pair's lists for `by`, after `change` when there is one, and the decision that change
       * made, for what the caller pushes.
       */
      const listsFor = (
        by: UserId,
        change?: { readonly change: ListCommand; readonly utcOffsetSeconds?: number },
      ) =>
        Effect.gen(function* () {
          const decision =
            change === undefined
              ? undefined
              : yield* changeList(by, change.change, change.utcOffsetSeconds);
          if (decision?._tag === "Rejected") {
            const reason = listRefusalOf(decision.rejection);
            return { result: ListsResult.cases.Refused.make({ reason }), decision };
          }
          if (!isMember(yield* store.load, by)) {
            return { result: ListsResult.cases.Refused.make({ reason: "NotOpen" }), decision };
          }
          const lists = yield* store.lists;
          return { result: ListsResult.cases.Done.make({ lists }), decision };
        });

      const setWish = (by: UserId, item: RoomItemId, wished: boolean, offered?: boolean) =>
        dispatch({
          _tag: "SetWish",
          by,
          item,
          wished,
          ...(offered === undefined ? {} : { offered }),
        });

      // The time is taken inside the lock, so the later of two check-ins is the one kept.
      const setMood = (by: UserId, request: SetMoodRequest) =>
        Effect.gen(function* () {
          const at = yield* Clock.currentTimeMillis;
          return yield* decideAndCommit({ _tag: "SetMood", by, at, ...request });
        }).pipe(lock.withPermits(1));

      /** Each member's latest check-in; none while the room is not open. */
      const moods: Effect.Effect<ReadonlyArray<MoodCheckIn>> = store.load.pipe(
        Effect.map((state) => (state._tag === "Active" ? state.moods : [])),
      );

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
        order,
        setWish,
        changeList,
        listsFor,
        lists: store.lists,
        forgetLists,
        setMood,
        moods,
        openGift,
        claimBonus,
        earn,
        creditPurchase,
        settled,
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
