import type { CatEntry, CatEvent } from "@billet/contracts-domain/cat";
import type { EpochMillis, IdempotencyKey, UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { PresenceState } from "@billet/contracts-realtime/client-message";
import type { RoomCommand } from "./room-command.ts";
import { RoomDecision, RoomOutput, RoomRejection } from "./room-decision.ts";
import type { ActiveRoom, Member, RoomCat, RoomState } from "./room-state.ts";
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
        },
        [RoomOutput.cases.RoomOpened.make({ pairId })],
      );
    }
    case "SendNote":
    case "SetPresence":
    case "SaveCat":
    case "RecordCatEvent":
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
      return accepted({ ...room, lastSeq: seq, cat: shared.cat }, [
        appended,
        RoomOutput.cases.CatEntryAppended.make({ entry: shared.entry }),
      ]);
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
      return accepted({ ...room, cat: next.cat }, [
        RoomOutput.cases.CatEntryAppended.make({ entry: next.entry }),
      ]);
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
