import { Schema } from "effect";
import { type CatEntry, type CatEvent, drawGuessGame } from "@billet/contracts-domain/cat";
import {
  type CoinEntry,
  CoinEntryId,
  type CoinEntryKind,
  dailyEarnCaps,
  type LocalDay,
  localDayOf,
  rewardFor,
  EarnRef,
  rewardForEarn,
  type EarnEvent,
} from "@billet/contracts-domain/coins";
import type { EpochMillis, IdempotencyKey, UserId } from "@billet/contracts-domain/ids";
import { freeInk, inkOf, type InkId } from "@billet/contracts-domain/inks";
import type { PriceBook, PriceTerms } from "@billet/contracts-domain/shop-catalog";
import { earnsOnTick } from "@billet/contracts-domain/list";
import { type MoodCheckIn, moodNoteMaxLength } from "@billet/contracts-domain/mood";
import type { Note } from "@billet/contracts-domain/note";
import type { PairId } from "@billet/contracts-domain/pair-id";
import {
  collectionOf,
  featuredSetAt,
  featuredSets,
  giftOn,
  itemPriceOn,
  pieceSetOf,
  roomItemOf,
  type RoomItemId,
  setPrice,
  soldIn,
  type ShopOffer,
  starterItems,
  treatGrams,
  treatPrice,
  welcomeCoins,
} from "@billet/contracts-domain/shop";
import type { PresenceState } from "@billet/contracts-realtime/client-message";
import { RoomCommand } from "./room-command.ts";
import { RoomDecision, RoomOutput, RoomRejection } from "./room-decision.ts";
import {
  type ActiveRoom,
  emptyWallet,
  type Member,
  type RoomCat,
  type RoomState,
  type RoomWallet,
} from "./room-state.ts";
import { newTemper, nextTemper } from "./cat-temper.ts";
import { addsInWindow, changeList } from "./lists.ts";

const accepted = (state: ActiveRoom, outputs: ReadonlyArray<RoomOutput> = []): RoomDecision =>
  RoomDecision.cases.Accepted.make({ state, outputs });

const rejected = (rejection: RoomRejection): RoomDecision =>
  RoomDecision.cases.Rejected.make({ rejection });

/** The one place that says who belongs in a room. */
export const isMember = (state: RoomState, user: UserId): boolean => {
  switch (state._tag) {
    case "Vacant":
      return false;
    case "Active":
      return state.members.some((member) => member.user === user);
  }
};

const isSameCouple = (
  room: ActiveRoom,
  pairId: PairId,
  [first, second]: readonly [UserId, UserId],
): boolean => room.pairId === pairId && isMember(room, first) && isMember(room, second);

/** Whether the pair may write in `ink`: the free one, or one it bought. */
export const ownsInk = (room: ActiveRoom, ink: InkId): boolean =>
  ink === freeInk || room.inks.includes(ink);

/** The ink a note is written in that the pair does not own, if any. Only text has an ink. */
const unownedInk = (room: ActiveRoom, note: Note): InkId | undefined => {
  switch (note._tag) {
    case "Text":
      return ownsInk(room, note.ink) ? undefined : note.ink;
    case "Drawing":
    case "Photo":
      return undefined;
  }
};

/** Whether the pair has the room piece: a starter, or one it bought. */
export const ownsItem = (room: ActiveRoom, item: RoomItemId): boolean =>
  starterItems.includes(item) || room.items.includes(item);

/** The pieces the pair has: the starters and the ones it bought or was given. */
const ownedItems = (room: ActiveRoom): ReadonlySet<string> =>
  new Set<string>([...starterItems, ...room.items]);

/**
 * What an order costs and gives, and the `ref` its wallet entry names. `offer` names a deal or a
 * set for the Inbox; a `treat` feeds the cat instead of granting anything.
 */
type Quote = {
  readonly price: number;
  readonly ref: string;
  readonly inks: ReadonlyArray<InkId>;
  readonly items: ReadonlyArray<RoomItemId>;
  readonly offer?: string;
  readonly treat?: true;
};

const hour = 3_600_000;

/** UTC offsets run from -12 to +14 hours: a featured set is on sale wherever its week is. */
const isFeaturedNow = (setId: string, at: EpochMillis): boolean =>
  featuredSetAt(at - 12 * hour).id === setId || featuredSetAt(at + 14 * hour).id === setId;

const inkSoldIn = (ink: InkId, book: PriceBook | undefined) => {
  if (book === undefined) return inkOf(ink);
  const found = book.inks.find((entry) => entry.id === ink);
  return found === undefined ? undefined : { price: found.price };
};

const quoteInk = (
  room: ActiveRoom,
  ink: InkId,
  book: PriceBook | undefined,
): Quote | RoomRejection => {
  // Owned first: the free ink is never in the catalog, and a deactivated ink is still owned.
  if (ownsInk(room, ink)) return RoomRejection.cases.AlreadyOwned.make({ ink });
  const sold = inkSoldIn(ink, book);
  if (sold === undefined) return RoomRejection.cases.NotSold.make({ ink });
  return { price: sold.price, ref: ink, inks: [ink], items: [] };
};

const quote = (
  room: ActiveRoom,
  offer: ShopOffer,
  at: EpochMillis,
  day: LocalDay,
  book: PriceBook | undefined,
): Quote | RoomRejection => {
  switch (offer._tag) {
    case "Ink":
      return quoteInk(room, offer.ink, book);
    case "Item": {
      const sold = soldIn(offer.item, book);
      if (sold === undefined) return RoomRejection.cases.NotOffered.make({});
      if (ownsItem(room, sold.id)) return RoomRejection.cases.OfferOwned.make({ offer: sold.id });
      const { price, deal } = itemPriceOn(sold, room.pairId, day, book);
      return {
        price,
        ref: sold.id,
        inks: [],
        items: [sold.id],
        ...(deal === undefined ? {} : { offer: `deal:${day}` }),
      };
    }
    case "Set": {
      const pieces = pieceSetOf(offer.set);
      if (pieces === undefined) return RoomRejection.cases.NotOffered.make({});
      const featured = featuredSets.some((entry) => entry.id === pieces.id);
      if (featured && !isFeaturedNow(pieces.id, at)) return RoomRejection.cases.NotOffered.make({});
      const owned = new Set<string>([...starterItems, ...room.items]);
      // A set sells only while every piece in it is on sale.
      if (book !== undefined && pieces.items.some((id) => soldIn(id, book) === undefined)) {
        return RoomRejection.cases.NotOffered.make({});
      }
      const price = setPrice(pieces, owned, book);
      if (price === undefined) return RoomRejection.cases.OfferOwned.make({ offer: pieces.id });
      const items = pieces.items.filter((item) => !owned.has(item));
      const offered = `${featured ? "featured" : "bundle"}:${pieces.id}`;
      return { price: price.price, ref: pieces.id, inks: [], items, offer: offered };
    }
    case "Treat":
      if (room.cat === undefined) return RoomRejection.cases.CatNotAdopted.make({});
      return { price: treatPrice, ref: "treat", inks: [], items: [], treat: true };
  }
};

/** Refuses a price above the one the buyer saw; a lower one stands. */
const checked = (bought: Quote | RoomRejection, terms: PriceTerms | undefined) =>
  !isRejection(bought) && terms?.expectedPrice !== undefined && bought.price > terms.expectedPrice
    ? RoomRejection.cases.PriceChanged.make({ price: bought.price })
    : bought;

/**
 * Takes the price and gives what was bought. A piece bought leaves the wishlist. A treat feeds the
 * cat on the spot, under the order's id; it was paid for, so the meal earns nothing back.
 */
const charge = (
  room: ActiveRoom,
  order: { readonly id: IdempotencyKey; readonly by: UserId; readonly at: EpochMillis },
  bought: Quote,
): RoomDecision => {
  const have = room.wallet.balance;
  if (bought.price > have) {
    return rejected(RoomRejection.cases.NotEnoughCoins.make({ needed: bought.price, have }));
  }
  const entry: CoinEntry = {
    id: decodeEntryId(`spend:${order.id}`),
    kind: "spend",
    amount: -bought.price,
    ref: bought.ref,
    at: order.at,
  };
  const wishlist = room.wishlist.filter((item) => !bought.items.includes(item));
  const fed =
    bought.treat === true && room.cat !== undefined
      ? journal(room.cat, {
          id: order.id,
          by: order.by,
          at: order.at,
          event: { _tag: "Fed", grams: treatGrams },
        })
      : undefined;
  const purchased = RoomOutput.cases.Purchased.make({
    id: order.id,
    by: order.by,
    at: order.at,
    items: bought.treat === true ? [bought.ref] : [...bought.inks, ...bought.items],
    ...(bought.offer === undefined ? {} : { offer: bought.offer }),
    coins: bought.price,
  });
  return accepted(
    {
      ...room,
      ...(fed === undefined ? {} : { cat: fed.cat }),
      inks: [...room.inks, ...bought.inks],
      items: [...room.items, ...bought.items],
      wishlist,
      wallet: { ...room.wallet, balance: have - bought.price },
    },
    [
      RoomOutput.cases.CoinsEntered.make({ entry }),
      ...(fed === undefined ? [] : [RoomOutput.cases.CatEntryAppended.make({ entry: fed.entry })]),
      ...(bought.inks.length === 0
        ? []
        : [RoomOutput.cases.InksGranted.make({ inks: bought.inks })]),
      ...(bought.items.length === 0
        ? []
        : [RoomOutput.cases.ItemsGranted.make({ items: bought.items })]),
      ...(wishlist.length === room.wishlist.length
        ? []
        : [RoomOutput.cases.WishlistChanged.make({ wishlist })]),
      purchased,
    ],
  );
};

const isRejection = (value: Quote | RoomRejection): value is RoomRejection => "_tag" in value;

const withPresence = (member: Member, user: UserId, presence: PresenceState): Member =>
  member.user === user ? { ...member, presence } : member;

/** Appends one entry to the cat's journal: the next `seq`, and the temper it leaves. */
const journal = (
  cat: RoomCat,
  draft: { id: IdempotencyKey; by: UserId; at: EpochMillis; event: CatEvent },
): { cat: RoomCat; entry: CatEntry } => {
  const seq = cat.lastSeq + 1;
  return {
    entry: { seq, ...draft },
    cat: {
      ...cat,
      temper: nextTemper(cat.temper, draft.event, draft.at, cat.lastAt),
      lastSeq: seq,
      lastAt: draft.at,
    },
  };
};

const decodeEntryId = Schema.decodeSync(CoinEntryId);

const coinEntry = (
  id: string,
  kind: CoinEntryKind,
  amount: number,
  ref: string,
  at: EpochMillis,
): CoinEntry => ({ id: decodeEntryId(id), kind, amount, ref, at });

/** The wallet with its earned counts for `day`: zero when the day has turned. */
const walletOn = (wallet: RoomWallet, day: LocalDay): RoomWallet =>
  wallet.day === day
    ? wallet
    : { balance: wallet.balance, day, care: 0, notes: 0, games: 0, lists: 0 };

const withCoins = (room: ActiveRoom, amount: number): ActiveRoom => ({
  ...room,
  wallet: { ...room.wallet, balance: room.wallet.balance + amount },
});

/** The offset a day is counted in: the caller's, else the cat's, else UTC. */
const offsetOf = (room: ActiveRoom, utcOffsetSeconds: number | undefined): number =>
  utcOffsetSeconds ?? room.cat?.profile.utcOffsetSeconds ?? 0;

/** Opens the day's gift: coins, or a piece with an amount-0 entry that names it. */
const openGift = (room: ActiveRoom, by: UserId, at: EpochMillis, day: LocalDay): RoomDecision => {
  const reward = giftOn(room.pairId, day, ownedItems(room));
  const opened = RoomOutput.cases.GiftOpened.make({ by, at, day, reward });
  const dated = { ...room, giftDay: day };
  switch (reward._tag) {
    case "Coins": {
      const entry = coinEntry(`gift:${day}`, "gift", reward.coins, day, at);
      return accepted(withCoins(dated, reward.coins), [
        RoomOutput.cases.CoinsEntered.make({ entry }),
        opened,
      ]);
    }
    case "Item": {
      const entry = coinEntry(`gift:${day}`, "gift", 0, reward.item, at);
      return accepted({ ...dated, items: [...dated.items, reward.item] }, [
        RoomOutput.cases.CoinsEntered.make({ entry }),
        RoomOutput.cases.ItemsGranted.make({ items: [reward.item] }),
        opened,
      ]);
    }
  }
};

/**
 * What a journal entry earns the pair: its reward, cut to what is left of the day's cap. The day is
 * the cat's local day, so the caps reset at the couple's midnight. Nothing when the cap is met.
 */
export const earnFor = (
  wallet: RoomWallet,
  entry: { id: string; at: EpochMillis; event: CatEvent },
  utcOffsetSeconds: number,
): { wallet: RoomWallet; coins?: CoinEntry } => {
  const reward = rewardFor(entry.event);
  if (reward === undefined) return { wallet };
  const day = localDayOf(entry.at, utcOffsetSeconds);
  const today = walletOn(wallet, day);
  const amount = Math.min(reward.coins, dailyEarnCaps[reward.source] - today[reward.source]);
  if (amount <= 0) return { wallet: today };
  return {
    wallet: {
      ...today,
      balance: today.balance + amount,
      [reward.source]: today[reward.source] + amount,
    },
    coins: {
      id: decodeEntryId(`earn:${entry.id}`),
      kind: "earn",
      amount,
      ref: entry.id,
      at: entry.at,
    },
  };
};

const coinsEntered = (coins: CoinEntry | undefined) =>
  coins === undefined ? [] : [RoomOutput.cases.CoinsEntered.make({ entry: coins })];

/** The room after a journal entry: the cat moved on, and the coins the entry earned. */
const cared = (room: ActiveRoom, cat: RoomCat, entry: CatEntry) => {
  const earned = earnFor(room.wallet, entry, cat.profile.utcOffsetSeconds);
  return {
    room: { ...room, cat, wallet: earned.wallet },
    outputs: [RoomOutput.cases.CatEntryAppended.make({ entry }), ...coinsEntered(earned.coins)],
  };
};

/**
 * What something the couple did in the app pays: its reward, cut to what is left of its day's cap.
 * Nothing when the cap is met. The caller makes sure it is paid once per ref.
 */
const appEarn = (
  room: ActiveRoom,
  at: EpochMillis,
  utcOffsetSeconds: number,
  event: EarnEvent,
): { room: ActiveRoom; outputs: ReadonlyArray<RoomOutput> } => {
  const reward = rewardForEarn(event);
  const today = walletOn(room.wallet, localDayOf(at, utcOffsetSeconds));
  const { source } = reward;
  const amount =
    source === undefined
      ? reward.coins
      : Math.min(reward.coins, dailyEarnCaps[source] - today[source]);
  if (amount <= 0) return { room: { ...room, wallet: today }, outputs: [] };
  const entry = coinEntry(reward.id, "earn", amount, reward.ref, at);
  const counted = source === undefined ? {} : { [source]: today[source] + amount };
  return {
    room: { ...room, wallet: { ...today, balance: today.balance + amount, ...counted } },
    outputs: [RoomOutput.cases.CoinsEntered.make({ entry })],
  };
};

const decodeEarnRef = Schema.decodeSync(EarnRef);

type ChangeListCommand = typeof RoomCommand.cases.ChangeList.Type;

/**
 * One change to a list. A tick earns, in the same decision, when its kind earns and the item has
 * not earned before; an add is an Inbox item, counted with `by`'s other adds of its window.
 */
const decideList = (room: ActiveRoom, command: ChangeListCommand): RoomDecision => {
  const { by, at, utcOffsetSeconds, change, list, paid } = command;
  if (!isMember(room, by)) return rejected(RoomRejection.cases.NotAMember.make({ user: by }));
  const outcome = changeList(list, by, at, change);
  switch (outcome._tag) {
    case "Unchanged":
      return accepted(room);
    case "Refused":
      return rejected(outcome.rejection);
    case "Deleted":
      return accepted(room, [
        RoomOutput.cases.ListDeleted.make({ list: outcome.list, key: change.key, at }),
      ]);
    case "Saved": {
      const saved = outcome.list;
      const outputs: Array<RoomOutput> = [
        RoomOutput.cases.ListSaved.make({ list: saved, key: change.key, at }),
      ];
      if (outcome.added !== undefined) {
        outputs.push(
          RoomOutput.cases.ListItemAdded.make({
            list: saved.id,
            kind: saved.kind,
            title: saved.title,
            by,
            slot: room.members[0].user === by ? 0 : 1,
            at,
            count: addsInWindow(saved, by, at),
            text: outcome.added.text,
          }),
        );
      }
      if (outcome.ticked === undefined || paid || !earnsOnTick(saved.kind)) {
        return accepted(room, outputs);
      }
      const event: EarnEvent = { _tag: "ListTicked", item: decodeEarnRef(outcome.ticked.id) };
      const earned = appEarn(room, at, utcOffsetSeconds, event);
      return accepted(earned.room, [...outputs, ...earned.outputs]);
    }
  }
};

const decideVacant = (command: RoomCommand): RoomDecision => {
  switch (command._tag) {
    case "Open": {
      const { pairId, members, joined } = command;
      const [first, second] = members;
      if (first === second) return rejected(RoomRejection.cases.DuplicateMember.make({}));
      return accepted(
        {
          _tag: "Active",
          pairId,
          members: [
            { user: first, presence: "idle" },
            { user: second, presence: "idle" },
          ],
          lastSeq: 0,
          streakDays: 0,
          inks: [],
          items: [],
          wishlist: [],
          bonuses: [],
          moods: [],
          welcomed: false,
          wallet: emptyWallet,
        },
        [RoomOutput.cases.RoomOpened.make(joined === undefined ? { pairId } : { pairId, joined })],
      );
    }
    case "SendNote":
    case "SetPresence":
    case "SaveCat":
    case "RecordCatEvent":
    case "GrantInks":
    case "GrantItems":
    case "Buy":
    case "Order":
    case "SetWish":
    case "React":
    case "Welcome":
    case "OpenGift":
    case "ClaimBonus":
    case "Earn":
    case "SetMood":
    case "CreditPurchase":
    case "ChangeList":
    case "SaveRiddle":
      return rejected(RoomRejection.cases.RoomNotOpen.make({}));
  }
};

const decideActive = (room: ActiveRoom, command: RoomCommand): RoomDecision => {
  switch (command._tag) {
    case "Open":
      if (command.members[0] === command.members[1])
        return rejected(RoomRejection.cases.DuplicateMember.make({}));
      // Pairing commits in D1 first, so it may repeat this call. A repeat is not a conflict.
      return isSameCouple(room, command.pairId, command.members)
        ? accepted(room)
        : rejected(RoomRejection.cases.RoomAlreadyOpen.make({}));
    case "SendNote": {
      const { note, key } = command;
      if (!isMember(room, note.author)) {
        return rejected(RoomRejection.cases.NotAMember.make({ user: note.author }));
      }
      const ink = unownedInk(room, note);
      if (ink !== undefined) return rejected(RoomRejection.cases.InkNotOwned.make({ ink }));
      const seq = room.lastSeq + 1;
      const appended = RoomOutput.cases.NoteAppended.make({ entry: { seq, note }, key });
      const event: CatEvent = { _tag: "NoteShared", note: note.id, kind: note._tag };
      if (room.cat === undefined) {
        // No cat yet, so no journal, but the note still earns. Its day is the UTC day until a cat
        // brings the couple's offset. Under the note's id: the partners may reuse each other's keys.
        const earned = earnFor(room.wallet, { id: note.id, at: note.sentAt, event }, 0);
        return accepted({ ...room, lastSeq: seq, wallet: earned.wallet }, [
          appended,
          ...coinsEntered(earned.coins),
        ]);
      }
      // With a cat, a note is also care: one journal entry, under the note's own key.
      const shared = journal(room.cat, { id: key, by: note.author, at: note.sentAt, event });
      const after = cared({ ...room, lastSeq: seq }, shared.cat, shared.entry);
      return accepted(after.room, [appended, ...after.outputs]);
    }
    case "SaveCat": {
      const { user, name, look, utcOffsetSeconds, natureSeed, at } = command;
      if (!isMember(room, user)) return rejected(RoomRejection.cases.NotAMember.make({ user }));
      // Birth and nature are the cat's for life: a later save changes only what can change.
      const cat: RoomCat =
        room.cat === undefined
          ? {
              profile: { name, look, utcOffsetSeconds, natureSeed, bornAt: at },
              temper: newTemper,
              lastSeq: 0,
            }
          : { ...room.cat, profile: { ...room.cat.profile, name, look, utcOffsetSeconds } };
      return accepted({ ...room, cat }, [
        RoomOutput.cases.CatSaved.make({
          cat: cat.profile,
          by: user,
          adopted: room.cat === undefined,
        }),
      ]);
    }
    case "RecordCatEvent": {
      const { by } = command;
      if (!isMember(room, by)) return rejected(RoomRejection.cases.NotAMember.make({ user: by }));
      const { id, at, event } = command;
      // The room pays draw-guess from the round itself; from an app it would be coins for nothing.
      if (event._tag === "GamePlayed" && event.game === drawGuessGame) {
        return rejected(RoomRejection.cases.RoomJournalsGame.make({}));
      }
      if (room.cat === undefined) return rejected(RoomRejection.cases.CatNotAdopted.make({}));
      const next = journal(room.cat, { id, by, at, event });
      const after = cared(room, next.cat, next.entry);
      return accepted(after.room, after.outputs);
    }
    case "SetPresence": {
      const { user, state } = command;
      if (!isMember(room, user)) return rejected(RoomRejection.cases.NotAMember.make({ user }));
      const [first, second] = room.members;
      const unchanged = room.members.some((m) => m.user === user && m.presence === state);
      return unchanged
        ? accepted(room)
        : accepted(
            {
              ...room,
              members: [withPresence(first, user, state), withPresence(second, user, state)],
            },
            [RoomOutput.cases.PresenceChanged.make({ user, state })],
          );
    }
    case "React": {
      const { by, note, current, reaction, at } = command;
      if (!isMember(room, by)) return rejected(RoomRejection.cases.NotAMember.make({ user: by }));
      if (note.author === by) return rejected(RoomRejection.cases.OwnNote.make({}));
      if (note._tag !== "Photo") return rejected(RoomRejection.cases.NotReactable.make({}));
      if (current?.reaction === reaction) {
        return current === undefined
          ? rejected(RoomRejection.cases.NoReaction.make({}))
          : accepted(room, [RoomOutput.cases.ReactionRepeated.make({ reaction: current })]);
      }
      const rev = (room.lastReactionRev ?? 0) + 1;
      return accepted({ ...room, lastReactionRev: rev }, [
        RoomOutput.cases.ReactionSet.make({
          reaction: { rev, note: note.id, by, at, ...(reaction === undefined ? {} : { reaction }) },
        }),
      ]);
    }
    case "GrantInks": {
      const added = [...new Set(command.inks)].filter((ink) => !ownsInk(room, ink));
      return added.length === 0
        ? accepted(room)
        : accepted({ ...room, inks: [...room.inks, ...added] }, [
            RoomOutput.cases.InksGranted.make({ inks: added }),
          ]);
    }
    case "GrantItems": {
      const added = [...new Set(command.items)].filter((item) => !ownsItem(room, item));
      return added.length === 0
        ? accepted(room)
        : accepted({ ...room, items: [...room.items, ...added] }, [
            RoomOutput.cases.ItemsGranted.make({ items: added }),
          ]);
    }
    case "Buy": {
      const { id, by, ink, at, terms } = command;
      if (!isMember(room, by)) return rejected(RoomRejection.cases.NotAMember.make({ user: by }));
      const bought = checked(quoteInk(room, ink, terms?.book), terms);
      return isRejection(bought) ? rejected(bought) : charge(room, { id, by, at }, bought);
    }
    case "Order": {
      const { id, by, offer, at, terms } = command;
      if (!isMember(room, by)) return rejected(RoomRejection.cases.NotAMember.make({ user: by }));
      const day = localDayOf(at, offsetOf(room, command.utcOffsetSeconds));
      const bought = checked(quote(room, offer, at, day, terms?.book), terms);
      return isRejection(bought) ? rejected(bought) : charge(room, { id, by, at }, bought);
    }
    case "SetWish": {
      const { by, item, wished } = command;
      if (!isMember(room, by)) return rejected(RoomRejection.cases.NotAMember.make({ user: by }));
      if (command.offered !== true && roomItemOf(item) === undefined)
        return rejected(RoomRejection.cases.NotOffered.make({}));
      const listed = room.wishlist.includes(item);
      if (listed === wished) return accepted(room);
      const wishlist = wished ? [...room.wishlist, item] : room.wishlist.filter((i) => i !== item);
      return accepted({ ...room, wishlist }, [RoomOutput.cases.WishlistChanged.make({ wishlist })]);
    }
    case "Welcome": {
      if (room.welcomed) return accepted(room);
      const entry = coinEntry("gift:welcome", "gift", welcomeCoins, "welcome", command.at);
      return accepted(withCoins({ ...room, welcomed: true }, welcomeCoins), [
        RoomOutput.cases.CoinsEntered.make({ entry }),
      ]);
    }
    case "OpenGift": {
      const { by, at, utcOffsetSeconds } = command;
      if (!isMember(room, by)) return rejected(RoomRejection.cases.NotAMember.make({ user: by }));
      const day = localDayOf(at, utcOffsetSeconds);
      if (room.giftDay === day) return rejected(RoomRejection.cases.GiftTaken.make({ day }));
      return openGift(room, by, at, day);
    }
    case "ClaimBonus": {
      const { by, at, collection } = command;
      if (!isMember(room, by)) return rejected(RoomRejection.cases.NotAMember.make({ user: by }));
      const sold = collectionOf(collection);
      if (sold === undefined) return rejected(RoomRejection.cases.NotOffered.make({}));
      if (room.bonuses.includes(sold.id)) {
        return rejected(RoomRejection.cases.BonusTaken.make({ collection: sold.id }));
      }
      const owned = ownedItems(room);
      if (!sold.items.every((item) => owned.has(item))) {
        return rejected(RoomRejection.cases.CollectionIncomplete.make({ collection: sold.id }));
      }
      const entry = coinEntry(`bonus:${sold.id}`, "bonus", sold.bonus, sold.id, at);
      return accepted(withCoins({ ...room, bonuses: [...room.bonuses, sold.id] }, sold.bonus), [
        RoomOutput.cases.CoinsEntered.make({ entry }),
        RoomOutput.cases.BonusPaid.make({ by, at, collection: sold.id, coins: sold.bonus }),
      ]);
    }
    case "Earn": {
      const { by, at, utcOffsetSeconds, event } = command;
      if (!isMember(room, by)) return rejected(RoomRejection.cases.NotAMember.make({ user: by }));
      const earned = appEarn(room, at, utcOffsetSeconds, event);
      return accepted(earned.room, earned.outputs);
    }
    case "ChangeList":
      return decideList(room, command);
    case "SetMood": {
      const { by, mood, at } = command;
      if (!isMember(room, by)) return rejected(RoomRejection.cases.NotAMember.make({ user: by }));
      const note = command.note?.trim() ?? "";
      if (note.length > moodNoteMaxLength) {
        return rejected(RoomRejection.cases.MoodNoteTooLong.make({}));
      }
      const checkIn: MoodCheckIn = { user: by, mood, ...(note === "" ? {} : { note }), at };
      // In the members' order, so the pair reads the same however the check-ins came in.
      const moods = room.members.flatMap(({ user }) =>
        user === by ? [checkIn] : room.moods.filter((earlier) => earlier.user === user),
      );
      return accepted({ ...room, moods }, [RoomOutput.cases.MoodSet.make({ checkIn })]);
    }
    case "SaveRiddle": {
      const { by, at, write, reward } = command;
      if (!isMember(room, by)) return rejected(RoomRejection.cases.NotAMember.make({ user: by }));
      const saved = RoomOutput.cases.RiddleSaved.make({ write });
      if (reward === undefined) return accepted(room, [saved]);
      const event: CatEvent = { _tag: "GamePlayed", game: drawGuessGame, ...reward };
      const id = write.riddle.id;
      if (room.cat === undefined) {
        // Like a note before the cat: no journal, but the round still pays, on the UTC day.
        const earned = earnFor(room.wallet, { id, at, event }, 0);
        return accepted({ ...room, wallet: earned.wallet }, [saved, ...coinsEntered(earned.coins)]);
      }
      const played = journal(room.cat, { id, by, at, event });
      const after = cared(room, played.cat, played.entry);
      return accepted(after.room, [saved, ...after.outputs]);
    }
    case "CreditPurchase": {
      const { id, kind, coins, ref, at } = command;
      // Apple refunds a pack after its coins may be spent, so a refund takes at most the balance
      // and its entry records what it took.
      const amount = kind === "buy" ? coins : -Math.min(coins, room.wallet.balance);
      const entry = coinEntry(id, kind, amount === 0 ? 0 : amount, ref, at);
      return accepted(withCoins(room, amount), [RoomOutput.cases.CoinsEntered.make({ entry })]);
    }
  }
};

/** Pure: same input, same output. Every effect the room has is named in the returned outputs. */
export const decide = (state: RoomState, command: RoomCommand): RoomDecision => {
  switch (state._tag) {
    case "Vacant":
      return decideVacant(command);
    case "Active":
      return decideActive(state, command);
  }
};
