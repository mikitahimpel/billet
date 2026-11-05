import { Context, Effect, Layer, Option, Schema } from "effect";
import { SecureRandom } from "effect/crypto";
import { MediaKey, type UserId } from "@billet/contracts-domain/ids";
import type { CompactStrokes } from "@billet/contracts-domain/ink";
import type { Note } from "@billet/contracts-domain/note";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { CoinEntry, CoinEntryId } from "@billet/contracts-domain/coins";
import { type GiftReward, RoomItemId } from "@billet/contracts-domain/shop";
import type {
  BuyRequest,
  BuyResponse,
  CoinsResponse,
  EarnRequest,
  EarnResponse,
} from "@billet/contracts-http-api/coins";
import type { InksResponse } from "@billet/contracts-http-api/inks";
import type {
  ClaimBonusRequest,
  ClaimBonusResponse,
  OpenGiftRequest,
  OpenGiftResponse,
  OrderRequest,
  OrderResponse,
  ShopResponse,
  WishRequest,
} from "@billet/contracts-http-api/shop";
import type { NoteEntry, SendNoteRequest } from "@billet/contracts-http-api/note";
import { freeInk, type InkId, inks as inkCatalog } from "@billet/contracts-domain/inks";
import { Metrics } from "@billet/backend-metrics/metrics";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import type { RoomDecision, RoomRejection } from "@billet/backend-pair-room/room-decision";
import type { PurchaseCredit } from "@billet/backend-pair-room/room-service";
import { shopOf } from "@billet/backend-pair-room/shop-view";
import { detectImageType, extensionOf } from "./image-type.ts";
import { MediaStore, mediaPrefix } from "./media-store.ts";
import {
  AlreadyOwned,
  BonusTaken,
  CatNotAdopted,
  CollectionIncomplete,
  GiftTaken,
  InkNotOwned,
  InvalidNote,
  NotEnoughCoins,
  NotesNotFound,
  NotesUnavailable,
} from "./notes-error.ts";
import { PairRooms } from "./pair-rooms.ts";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";

/** The most a compact rendition may take as JSON, matching the iOS encoder's budget. */
export const compactBudget = 3072;

const encoder = new TextEncoder();

const compactFits = (compact: CompactStrokes) =>
  encoder.encode(JSON.stringify(compact)).length <= compactBudget;

const decodeMediaKey = Schema.decodeSync(MediaKey);

const belongsTo = (pairId: PairId, key: MediaKey) => key.startsWith(mediaPrefix(pairId));

const decodeItemId = Schema.decodeSync(RoomItemId);

const isNotOpen = (decision: RoomDecision) =>
  decision._tag === "Rejected" && decision.rejection._tag === "RoomNotOpen";

const directoryUnavailable = () => new NotesUnavailable({ reason: "directory-unavailable" });

/**
 * Notes and their images, for the caller's own pair. Every method starts from the pair that D1 says
 * the caller belongs to, never from one the client names, so one couple can't reach another's room
 * or prefix.
 */
export class NotesService extends Context.Service<
  NotesService,
  {
    /**
     * Stores a PNG, JPEG or HEIC under the couple's prefix and returns its new key, which ends in
     * the extension of the format its signature declares.
     */
    readonly uploadImage: (
      userId: UserId,
      bytes: Uint8Array,
    ) => Effect.Effect<MediaKey, NotesNotFound | InvalidNote | NotesUnavailable>;
    readonly readImage: (
      userId: UserId,
      key: MediaKey,
    ) => Effect.Effect<Uint8Array, NotesNotFound | NotesUnavailable>;
    /** Appends a note to the room. Its image must already be in the couple's prefix. */
    readonly sendNote: (
      userId: UserId,
      request: SendNoteRequest,
    ) => Effect.Effect<Note, NotesNotFound | InvalidNote | InkNotOwned | NotesUnavailable>;
    /** Every ink the shop sells, and the ones the caller's pair owns: the free ink first. */
    readonly inks: (
      userId: UserId,
    ) => Effect.Effect<InksResponse, NotesNotFound | NotesUnavailable>;
    /** The pair's coin balance and its wallet entries after `after`, oldest first. */
    readonly coins: (
      userId: UserId,
      after: CoinEntryId | undefined,
      limit: number,
    ) => Effect.Effect<CoinsResponse, NotesNotFound | NotesUnavailable>;
    /** Buys one ink with the pair's coins. A retried `id` answers with the first buy. */
    readonly buy: (
      userId: UserId,
      request: BuyRequest,
    ) => Effect.Effect<
      BuyResponse,
      NotesNotFound | NotEnoughCoins | AlreadyOwned | NotesUnavailable
    >;
    /** What the caller's pair has: balance, inks, room pieces and wishlist. */
    readonly shop: (
      userId: UserId,
    ) => Effect.Effect<ShopResponse, NotesNotFound | NotesUnavailable>;
    /** Buys one offer with the pair's coins. A retried `id` answers with the first order. */
    readonly order: (
      userId: UserId,
      request: OrderRequest,
    ) => Effect.Effect<
      OrderResponse,
      NotesNotFound | NotEnoughCoins | AlreadyOwned | CatNotAdopted | NotesUnavailable
    >;
    /** Opens the day's gift. The partner's open, or a retry, answers with the first. */
    readonly openGift: (
      userId: UserId,
      request: OpenGiftRequest,
    ) => Effect.Effect<OpenGiftResponse, NotesNotFound | GiftTaken | NotesUnavailable>;
    /** Collects a complete collection's bonus. Asking again answers with the bonus paid. */
    readonly claimBonus: (
      userId: UserId,
      request: ClaimBonusRequest,
    ) => Effect.Effect<
      ClaimBonusResponse,
      NotesNotFound | CollectionIncomplete | BonusTaken | NotesUnavailable
    >;
    /** Pays an app earn once per ref, within the day's cap. */
    readonly earn: (
      userId: UserId,
      request: EarnRequest,
    ) => Effect.Effect<EarnResponse, NotesNotFound | NotesUnavailable>;
    readonly setWish: (
      userId: UserId,
      request: WishRequest,
    ) => Effect.Effect<ShopResponse, NotesNotFound | NotesUnavailable>;
    /** The balance of a pair's wallet. Payments asks by pair, never by caller. */
    readonly walletBalance: (
      pairId: PairId,
    ) => Effect.Effect<number, NotesNotFound | NotesUnavailable>;
    /**
     * Enters coins bought with money in a pair's wallet, once per entry id, and answers the
     * balance after it and the coins the entry moved, as a positive number.
     */
    readonly creditPurchase: (
      pairId: PairId,
      credit: PurchaseCredit,
    ) => Effect.Effect<
      { readonly balance: number; readonly coins: number },
      NotesNotFound | NotesUnavailable
    >;
    /** The couple's notes with `seq` above `afterSeq`, oldest first. */
    readonly history: (
      userId: UserId,
      afterSeq: number,
      limit: number,
    ) => Effect.Effect<ReadonlyArray<NoteEntry>, NotesNotFound | NotesUnavailable>;
  }
>()("@billet/backend-notes/NotesService") {
  static readonly layer: Layer.Layer<
    NotesService,
    never,
    PairingRepository | MediaStore | PairRooms | Metrics | SecureRandom.SecureRandom
  > = Layer.effect(
    NotesService,
    Effect.gen(function* () {
      const pairing = yield* PairingRepository;
      const media = yield* MediaStore;
      const rooms = yield* PairRooms;
      const metrics = yield* Metrics;
      const random = yield* SecureRandom.SecureRandom;

      const pairOf = (userId: UserId) =>
        pairing.findPair(userId).pipe(
          Effect.mapError(directoryUnavailable),
          Effect.flatMap(
            Option.match({
              onNone: () => Effect.fail(new NotesNotFound()),
              onSome: (pairId) => Effect.as(annotateRefs({ pair: pairId }), pairId),
            }),
          ),
        );

      // Pairing commits in D1 and never reaches the room, so a couple's first note opens it. Two
      // first notes at once both open it, and a repeated open is accepted.
      const openRoom = Effect.fn("NotesService.openRoom")(function* (pairId: PairId) {
        const members = yield* pairing
          .findMembers(pairId)
          .pipe(Effect.mapError(directoryUnavailable));
        const [first, second] = members;
        if (first === undefined || second === undefined) {
          return yield* Effect.fail(new NotesNotFound());
        }
        yield* rooms.open(pairId, [first, second]);
      });

      const uploadImage = Effect.fn("NotesService.uploadImage")(function* (
        userId: UserId,
        bytes: Uint8Array,
      ): Effect.fn.Return<MediaKey, NotesNotFound | InvalidNote | NotesUnavailable> {
        const pairId = yield* pairOf(userId);
        const type = detectImageType(bytes);
        if (type === undefined) return yield* Effect.fail(new InvalidNote());
        const id = yield* random.uuidV4();
        const key = decodeMediaKey(`${mediaPrefix(pairId)}notes/${id}.${extensionOf(type)}`);
        yield* media.put(key, bytes, userId);
        return key;
      });

      const readImage = Effect.fn("NotesService.readImage")(function* (
        userId: UserId,
        key: MediaKey,
      ): Effect.fn.Return<Uint8Array, NotesNotFound | NotesUnavailable> {
        const pairId = yield* pairOf(userId);
        if (!belongsTo(pairId, key)) return yield* Effect.fail(new NotesNotFound());
        const image = yield* media.get(key);
        return yield* Option.match(image, {
          onNone: () => Effect.fail(new NotesNotFound()),
          onSome: (bytes) => Effect.succeed(bytes),
        });
      });

      const sendNote = Effect.fn("NotesService.sendNote")(function* (
        userId: UserId,
        request: SendNoteRequest,
      ): Effect.fn.Return<Note, NotesNotFound | InvalidNote | InkNotOwned | NotesUnavailable> {
        const pairId = yield* pairOf(userId);
        if (request._tag === "Drawing" && !compactFits(request.compact)) {
          return yield* Effect.fail(new InvalidNote());
        }
        // A text note carries its words; drawings and photos point at an image already uploaded.
        if (
          request._tag !== "Text" &&
          (!belongsTo(pairId, request.image) || !(yield* media.has(request.image)))
        ) {
          return yield* Effect.fail(new NotesNotFound());
        }

        const attempt = yield* rooms.sendNote(pairId, userId, request);
        const decision = isNotOpen(attempt)
          ? yield* openRoom(pairId).pipe(Effect.andThen(rooms.sendNote(pairId, userId, request)))
          : attempt;

        switch (decision._tag) {
          case "Accepted": {
            for (const output of decision.outputs) {
              // A repeated send is the same note: it is counted once, when it was stored.
              if (output._tag === "NoteAppended") {
                yield* metrics.record({ userId, pairId, name: "NoteSent" });
                return output.entry.note;
              }
              if (output._tag === "NoteRepeated") return output.entry.note;
            }
            return yield* Effect.fail(new NotesUnavailable({ reason: "note-not-appended" }));
          }
          case "Rejected":
            return yield* decision.rejection._tag === "InkNotOwned"
              ? Effect.fail(new InkNotOwned({ ink: decision.rejection.ink }))
              : Effect.fail(new NotesUnavailable({ reason: "room-refused-note" }));
        }
      });

      const history = Effect.fn("NotesService.history")(function* (
        userId: UserId,
        afterSeq: number,
        limit: number,
      ): Effect.fn.Return<ReadonlyArray<NoteEntry>, NotesNotFound | NotesUnavailable> {
        const pairId = yield* pairOf(userId);
        return yield* rooms.notesAfter(pairId, afterSeq, limit);
      });

      const owned = (bought: ReadonlyArray<InkId>) => [
        freeInk,
        ...bought.filter((ink) => ink !== freeInk),
      ];

      const inks = Effect.fn("NotesService.inks")(function* (
        userId: UserId,
      ): Effect.fn.Return<InksResponse, NotesNotFound | NotesUnavailable> {
        const pairId = yield* pairOf(userId);
        const bought = yield* rooms.inks(pairId);
        return { inks: inkCatalog, owned: owned(bought) };
      });

      const coins = Effect.fn("NotesService.coins")(function* (
        userId: UserId,
        after: CoinEntryId | undefined,
        limit: number,
      ): Effect.fn.Return<CoinsResponse, NotesNotFound | NotesUnavailable> {
        const pairId = yield* pairOf(userId);
        return yield* openedRead(pairId, () => rooms.coins(pairId, after, limit));
      });

      // A refused spend: what the client can act on, or the room's fault.
      const refusedSpend = (rejection: RoomRejection) => {
        switch (rejection._tag) {
          case "NotEnoughCoins":
            return new NotEnoughCoins({ needed: rejection.needed, have: rejection.have });
          case "AlreadyOwned":
            return new AlreadyOwned({ itemId: rejection.ink });
          case "OfferOwned":
            return new AlreadyOwned({ itemId: rejection.offer });
          case "NotSold":
          case "NotOffered":
            return new NotesNotFound();
          case "CatNotAdopted":
            return new CatNotAdopted();
          case "RoomNotOpen":
          case "NotAMember":
          case "DuplicateMember":
          case "RoomAlreadyOpen":
          case "CatEntryIdTaken":
          case "InkNotOwned":
          case "NoteNotFound":
          case "OwnNote":
          case "NotReactable":
          case "NoReaction":
          // The service answers a repeat with the first entry before the room decides.
          case "GiftTaken":
          case "BonusTaken":
          case "CollectionIncomplete":
          case "MoodNoteTooLong":
            return new NotesUnavailable({ reason: "room-refused-buy" });
        }
      };

      // Reading a pair's shop or wallet opens its room, so its welcome coins show on the first read.
      const openedRead = <A>(
        pairId: PairId,
        read: () => Effect.Effect<A | null, NotesUnavailable>,
      ): Effect.Effect<A, NotesNotFound | NotesUnavailable> =>
        Effect.gen(function* () {
          const first = yield* read();
          if (first !== null) return first;
          yield* openRoom(pairId);
          const opened = yield* read();
          return opened ?? (yield* Effect.fail(new NotesUnavailable({ reason: "room-not-open" })));
        });

      // Pairing never reaches the room, so a spend or a wish before the first note opens it.
      const inOpenRoom = (
        pairId: PairId,
        attempt: () => Effect.Effect<RoomDecision, NotesUnavailable>,
      ) =>
        Effect.flatMap(attempt(), (decision) =>
          isNotOpen(decision)
            ? openRoom(pairId).pipe(Effect.andThen(attempt()))
            : Effect.succeed(decision),
        );

      /** The entry of `kind` an accepted decision entered, or the first one a retry repeats. */
      const entryOf = (
        decision: RoomDecision & { readonly _tag: "Accepted" },
        kind: CoinEntry["kind"],
      ) => {
        for (const output of decision.outputs) {
          if (output._tag === "CoinsEntered" && output.entry.kind === kind) return output.entry;
          if (output._tag === "CoinsRepeated") return output.entry;
        }
        return undefined;
      };

      const spendOf = (decision: RoomDecision & { readonly _tag: "Accepted" }) =>
        entryOf(decision, "spend");

      // The room prices the buy from the catalog; the client's idea of the price never reaches it.
      const buy = Effect.fn("NotesService.buy")(function* (
        userId: UserId,
        request: BuyRequest,
      ): Effect.fn.Return<
        BuyResponse,
        NotesNotFound | NotEnoughCoins | AlreadyOwned | NotesUnavailable
      > {
        const pairId = yield* pairOf(userId);
        const decision = yield* inOpenRoom(pairId, () =>
          rooms.buy(pairId, userId, request.id, request.item),
        );
        if (decision._tag === "Rejected") {
          const refused = refusedSpend(decision.rejection);
          // An ink is never for the cat.
          return yield* Effect.fail(
            refused._tag === "CatNotAdopted"
              ? new NotesUnavailable({ reason: "room-refused-buy" })
              : refused,
          );
        }
        const { state, outputs } = decision;
        const entry = spendOf(decision);
        if (entry === undefined) {
          return yield* Effect.fail(new NotesUnavailable({ reason: "buy-not-entered" }));
        }
        // A retry answers as the first buy did, with today's balance.
        const granted = outputs.some((output) => output._tag === "CoinsRepeated")
          ? state.inks.filter((ink) => ink === entry.ref)
          : outputs.flatMap((output) => (output._tag === "InksGranted" ? output.inks : []));
        return { entry, balance: state.wallet.balance, granted, owned: owned(state.inks) };
      });

      const shop = Effect.fn("NotesService.shop")(function* (
        userId: UserId,
      ): Effect.fn.Return<ShopResponse, NotesNotFound | NotesUnavailable> {
        const pairId = yield* pairOf(userId);
        return yield* openedRead(pairId, () => rooms.shop(pairId));
      });

      const order = Effect.fn("NotesService.order")(function* (
        userId: UserId,
        request: OrderRequest,
      ): Effect.fn.Return<
        OrderResponse,
        NotesNotFound | NotEnoughCoins | AlreadyOwned | CatNotAdopted | NotesUnavailable
      > {
        const pairId = yield* pairOf(userId);
        const decision = yield* inOpenRoom(pairId, () =>
          rooms.order(pairId, userId, request.id, request.offer, request.utcOffsetSeconds),
        );
        if (decision._tag === "Rejected")
          return yield* Effect.fail(refusedSpend(decision.rejection));
        const entry = spendOf(decision);
        if (entry === undefined) {
          return yield* Effect.fail(new NotesUnavailable({ reason: "order-not-entered" }));
        }
        return { entry, shop: shopOf(decision.state) };
      });

      const setWish = Effect.fn("NotesService.setWish")(function* (
        userId: UserId,
        request: WishRequest,
      ): Effect.fn.Return<ShopResponse, NotesNotFound | NotesUnavailable> {
        const pairId = yield* pairOf(userId);
        const decision = yield* inOpenRoom(pairId, () =>
          rooms.setWish(pairId, userId, request.item, request.wished),
        );
        return decision._tag === "Accepted"
          ? shopOf(decision.state)
          : yield* Effect.fail(new NotesUnavailable({ reason: "room-refused-wish" }));
      });

      /** What a gift entry gave: its coins, or the piece an amount-0 entry names. */
      const rewardOf = (entry: CoinEntry): GiftReward =>
        entry.amount > 0
          ? { _tag: "Coins", coins: entry.amount }
          : { _tag: "Item", item: decodeItemId(entry.ref) };

      const openGift = Effect.fn("NotesService.openGift")(function* (
        userId: UserId,
        request: OpenGiftRequest,
      ): Effect.fn.Return<OpenGiftResponse, NotesNotFound | GiftTaken | NotesUnavailable> {
        const pairId = yield* pairOf(userId);
        const decision = yield* inOpenRoom(pairId, () =>
          rooms.openGift(pairId, userId, request.utcOffsetSeconds),
        );
        if (decision._tag === "Rejected") {
          const { rejection } = decision;
          return yield* Effect.fail(
            rejection._tag === "GiftTaken"
              ? new GiftTaken({ day: rejection.day })
              : new NotesUnavailable({ reason: "room-refused-gift" }),
          );
        }
        const entry = entryOf(decision, "gift");
        if (entry === undefined) {
          return yield* Effect.fail(new NotesUnavailable({ reason: "gift-not-entered" }));
        }
        const opened = decision.outputs.find((output) => output._tag === "GiftOpened");
        const reward = opened?._tag === "GiftOpened" ? opened.reward : rewardOf(entry);
        return { entry, reward, shop: shopOf(decision.state) };
      });

      const claimBonus = Effect.fn("NotesService.claimBonus")(function* (
        userId: UserId,
        request: ClaimBonusRequest,
      ): Effect.fn.Return<
        ClaimBonusResponse,
        NotesNotFound | CollectionIncomplete | BonusTaken | NotesUnavailable
      > {
        const pairId = yield* pairOf(userId);
        const decision = yield* inOpenRoom(pairId, () =>
          rooms.claimBonus(pairId, userId, request.collection),
        );
        if (decision._tag === "Rejected") {
          const { rejection } = decision;
          return yield* Effect.fail(
            rejection._tag === "CollectionIncomplete"
              ? new CollectionIncomplete({ collection: rejection.collection })
              : rejection._tag === "BonusTaken"
                ? new BonusTaken({ collection: rejection.collection })
                : rejection._tag === "NotOffered"
                  ? new NotesNotFound()
                  : new NotesUnavailable({ reason: "room-refused-bonus" }),
          );
        }
        const entry = entryOf(decision, "bonus");
        if (entry === undefined) {
          return yield* Effect.fail(new NotesUnavailable({ reason: "bonus-not-entered" }));
        }
        return { entry, shop: shopOf(decision.state) };
      });

      const earn = Effect.fn("NotesService.earn")(function* (
        userId: UserId,
        request: EarnRequest,
      ): Effect.fn.Return<EarnResponse, NotesNotFound | NotesUnavailable> {
        const pairId = yield* pairOf(userId);
        const decision = yield* inOpenRoom(pairId, () =>
          rooms.earn(pairId, userId, request.event, request.utcOffsetSeconds),
        );
        if (decision._tag === "Rejected") {
          return yield* Effect.fail(new NotesUnavailable({ reason: "room-refused-earn" }));
        }
        // No entry when the day's cap was already met.
        const entry = entryOf(decision, "earn");
        return {
          balance: decision.state.wallet.balance,
          ...(entry === undefined ? {} : { entry }),
        };
      });

      const walletBalance = Effect.fn("NotesService.walletBalance")(function* (pairId: PairId) {
        return (yield* openedRead(pairId, () => rooms.shop(pairId))).balance;
      });

      const creditPurchase = Effect.fn("NotesService.creditPurchase")(function* (
        pairId: PairId,
        credit: PurchaseCredit,
      ) {
        const decision = yield* inOpenRoom(pairId, () => rooms.creditPurchase(pairId, credit));
        if (decision._tag === "Rejected") {
          return yield* Effect.fail(new NotesUnavailable({ reason: "room-refused-purchase" }));
        }
        const entry = entryOf(decision, credit.kind);
        if (entry === undefined) {
          return yield* Effect.fail(new NotesUnavailable({ reason: "purchase-not-entered" }));
        }
        return { balance: decision.state.wallet.balance, coins: Math.abs(entry.amount) };
      });

      return NotesService.of({
        uploadImage,
        readImage,
        sendNote,
        inks,
        coins,
        buy,
        shop,
        order,
        setWish,
        openGift,
        claimBonus,
        earn,
        walletBalance,
        creditPurchase,
        history,
      });
    }),
  );
}
