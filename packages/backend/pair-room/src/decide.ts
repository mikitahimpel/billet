import { Schema } from "effect";
import type { CatEntry, CatEvent } from "@billet/contracts-domain/cat";
import {
  type CoinEntry,
  CoinEntryId,
  dailyEarnCaps,
  localDayOf,
  rewardFor,
} from "@billet/contracts-domain/coins";
import type { EpochMillis, IdempotencyKey, UserId } from "@billet/contracts-domain/ids";
import { freeInk, inkOf, type InkId } from "@billet/contracts-domain/inks";
import type { Note } from "@billet/contracts-domain/note";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { PresenceState } from "@billet/contracts-realtime/client-message";
import type { RoomCommand } from "./room-command.ts";
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

/**
 * What a journal entry earns the pair: its reward, cut to what is left of the day's cap. The day is
 * the cat's local day, so the caps reset at the couple's midnight. Nothing when the cap is met.
 */
export const earnFor = (
  wallet: RoomWallet,
  entry: CatEntry,
  utcOffsetSeconds: number,
): { wallet: RoomWallet; coins?: CoinEntry } => {
  const reward = rewardFor(entry.event);
  if (reward === undefined) return { wallet };
  const day = localDayOf(entry.at, utcOffsetSeconds);
  const today: RoomWallet =
    wallet.day === day ? wallet : { balance: wallet.balance, day, care: 0, notes: 0, games: 0 };
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

/** The room after a journal entry: the cat moved on, and the coins the entry earned. */
const cared = (room: ActiveRoom, cat: RoomCat, entry: CatEntry) => {
  const earned = earnFor(room.wallet, entry, cat.profile.utcOffsetSeconds);
  return {
    room: { ...room, cat, wallet: earned.wallet },
    outputs: [
      RoomOutput.cases.CatEntryAppended.make({ entry }),
      ...(earned.coins === undefined
        ? []
        : [RoomOutput.cases.CoinsEntered.make({ entry: earned.coins })]),
    ],
  };
};

const decideVacant = (command: RoomCommand): RoomDecision => {
  switch (command._tag) {
    case "Open": {
      const { pairId, members } = command;
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
          wallet: emptyWallet,
        },
        [RoomOutput.cases.RoomOpened.make({ pairId })],
      );
    }
    case "SendNote":
    case "SetPresence":
    case "SaveCat":
    case "RecordCatEvent":
    case "GrantInks":
    case "Buy":
    case "React":
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
      // With a cat, a note is also care: one journal entry, under the note's own key.
      if (room.cat === undefined) return accepted({ ...room, lastSeq: seq }, [appended]);
      const shared = journal(room.cat, {
        id: key,
        by: note.author,
        at: note.sentAt,
        event: { _tag: "NoteShared", note: note.id, kind: note._tag },
      });
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
      if (room.cat === undefined) return rejected(RoomRejection.cases.CatNotAdopted.make({}));
      const { id, at, event } = command;
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
    case "Buy": {
      const { id, by, ink, at } = command;
      if (!isMember(room, by)) return rejected(RoomRejection.cases.NotAMember.make({ user: by }));
      const sold = inkOf(ink);
      if (sold === undefined) return rejected(RoomRejection.cases.NotSold.make({ ink }));
      if (ownsInk(room, ink)) return rejected(RoomRejection.cases.AlreadyOwned.make({ ink }));
      const have = room.wallet.balance;
      if (sold.price > have) {
        return rejected(RoomRejection.cases.NotEnoughCoins.make({ needed: sold.price, have }));
      }
      const entry: CoinEntry = {
        id: decodeEntryId(`spend:${id}`),
        kind: "spend",
        amount: -sold.price,
        ref: ink,
        at,
      };
      return accepted(
        {
          ...room,
          inks: [...room.inks, ink],
          wallet: { ...room.wallet, balance: have - sold.price },
        },
        [
          RoomOutput.cases.CoinsEntered.make({ entry }),
          RoomOutput.cases.InksGranted.make({ inks: [ink] }),
        ],
      );
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
