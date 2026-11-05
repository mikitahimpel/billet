import { Schema } from "effect";
import {
  ActivityCursor,
  ActivityEvent,
  ActivityId,
  ActivityTarget,
  activityRetentionDays,
  type ActivityActor,
  type ActivityItem,
} from "@billet/contracts-domain/activity";
import type { CatEntry } from "@billet/contracts-domain/cat";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import type { Note } from "@billet/contracts-domain/note";
import type { RoomOutput } from "./room-decision.ts";

/** Who did it, as stored: a member, the cat on its own, or the App Store. */
export const ActivityDoer = Schema.TaggedUnion({
  Member: { user: UserId },
  Cat: {},
  Store: {},
});
export type ActivityDoer = typeof ActivityDoer.Type;

/** One stored Inbox item. The caller sees `doer` as `Me`, `Partner`, `Cat` or `Store`. */
export const ActivityRow = Schema.Struct({
  id: ActivityId,
  at: EpochMillis,
  doer: ActivityDoer,
  event: ActivityEvent,
  target: Schema.optionalKey(ActivityTarget),
});
export type ActivityRow = typeof ActivityRow.Type;

const decodeId = Schema.decodeSync(ActivityId);
const decodeCursor = Schema.decodeSync(ActivityCursor);

/** How long an item is kept. */
export const activityRetentionMillis = activityRetentionDays * 86_400_000;

/** The place of a row in the list: sorts as the list does, by time, then by id. */
export const cursorOf = (row: Pick<ActivityRow, "at" | "id">): ActivityCursor =>
  decodeCursor(`${String(row.at).padStart(16, "0")}~${row.id}`);

const member = (user: UserId): ActivityDoer => ({ _tag: "Member", user });

/** A journal entry's item. A note's entry has none: the note makes its own. */
export const activityForCatEntry = (entry: CatEntry): ActivityRow | undefined => {
  const base = { id: decodeId(`cat:${entry.id}`), at: entry.at, doer: member(entry.by) };
  const cat = { target: ActivityTarget.cases.Cat.make({}) };
  const { event } = entry;
  switch (event._tag) {
    case "Fed":
      return { ...base, ...cat, event: { _tag: "CatFed", grams: event.grams } };
    case "Petted":
      return { ...base, ...cat, event: { _tag: "CatPetted" } };
    case "Played":
      return { ...base, ...cat, event: { _tag: "CatPlayed" } };
    case "GamePlayed":
      return {
        ...base,
        ...cat,
        event: { _tag: "CatGamePlayed", game: event.game, score: event.score, won: event.won },
      };
    case "Slept":
      return { ...base, ...cat, event: { _tag: "CatSlept" } };
    case "Shooed":
      return { ...base, ...cat, event: { _tag: "CatShooed" } };
    // The one plant by the window has no id yet; plants with ids bring their own target.
    case "Watered":
      return { ...base, event: { _tag: "PlantWatered" } };
    case "NoteShared":
      return undefined;
  }
};

/** A note's item: a text note opens the note, a drawing or a photo opens Moments. */
export const activityForNote = (note: Note): ActivityRow => ({
  id: decodeId(`note:${note.id}`),
  at: note.sentAt,
  doer: member(note.author),
  event: { _tag: "NoteSent", note: note.id, kind: note._tag },
  target:
    note._tag === "Text"
      ? ActivityTarget.cases.Note.make({ note: note.id })
      : ActivityTarget.cases.Moments.make({ note: note.id }),
});

/**
 * The items an accepted decision adds, in the order of its outputs. `at` is the room's time for
 * outputs that carry none of their own (a save of the cat).
 */
export const activityOf = (
  outputs: ReadonlyArray<RoomOutput>,
  at: EpochMillis,
): ReadonlyArray<ActivityRow> =>
  outputs.flatMap((output): ReadonlyArray<ActivityRow> => {
    switch (output._tag) {
      case "NoteAppended":
        return [activityForNote(output.entry.note)];
      case "CatEntryAppended": {
        const row = activityForCatEntry(output.entry);
        return row === undefined ? [] : [row];
      }
      case "CatSaved": {
        const { cat, by, adopted } = output;
        // A burst of saves while typing is one item per minute, and the last name wins: rows
        // are written over by id.
        const minute = Math.floor(at / 60_000);
        return [
          {
            id: decodeId(`cat:${adopted ? "adopted" : `named-${minute}`}`),
            at,
            doer: member(by),
            event: adopted
              ? { _tag: "CatAdopted", name: cat.name }
              : { _tag: "CatRenamed", name: cat.name },
            target: ActivityTarget.cases.Cat.make({}),
          },
        ];
      }
      case "RoomOpened":
      case "NoteRepeated":
      case "PresenceChanged":
      case "CatEntryRepeated":
      case "InksGranted":
        return [];
    }
  });

/** The row as `caller` sees it. */
export const itemFor = (row: ActivityRow, caller: UserId): ActivityItem => {
  const actor: ActivityActor =
    row.doer._tag === "Member" ? (row.doer.user === caller ? "Me" : "Partner") : row.doer._tag;
  return {
    id: row.id,
    at: row.at,
    actor,
    event: row.event,
    ...(row.target === undefined ? {} : { target: row.target }),
    cursor: cursorOf(row),
  };
};

/** Whether `caller` has an item to read in `row`: one they did not make themselves. */
export const countsAsUnread = (row: ActivityRow, caller: UserId): boolean =>
  row.doer._tag !== "Member" || row.doer.user !== caller;
