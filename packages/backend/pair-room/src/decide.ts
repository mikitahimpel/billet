import type { UserId } from "@billet/contracts-domain/ids";
import { freeInk, type InkId } from "@billet/contracts-domain/inks";
import type { Note } from "@billet/contracts-domain/note";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { PresenceState } from "@billet/contracts-realtime/client-message";
import type { RoomCommand } from "./room-command.ts";
import { RoomDecision, RoomOutput, RoomRejection } from "./room-decision.ts";
import type { ActiveRoom, Member, RoomState } from "./room-state.ts";

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
        },
        [RoomOutput.cases.RoomOpened.make({ pairId })],
      );
    }
    case "SendNote":
    case "SetPresence":
    case "GrantInks":
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
      return accepted({ ...room, lastSeq: seq }, [
        RoomOutput.cases.NoteAppended.make({ entry: { seq, note }, key }),
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
    case "GrantInks": {
      const added = [...new Set(command.inks)].filter((ink) => !ownsInk(room, ink));
      return added.length === 0
        ? accepted(room)
        : accepted({ ...room, inks: [...room.inks, ...added] }, [
            RoomOutput.cases.InksGranted.make({ inks: added }),
          ]);
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
