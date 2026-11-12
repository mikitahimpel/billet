// The NotificationService extension reads `PushPayload` beside `aps`
// (apps/ios/Shared/Model/Drawings.swift); the Live Activity decodes `content-state`.
import { Schema } from "effect";
import type { Note } from "@billet/contracts-domain/note";
import type { UserId } from "@billet/contracts-domain/ids";
import type { Reaction } from "@billet/contracts-domain/reaction";
import type { LoveStreak } from "@billet/contracts-domain/streak";
import { PushPayload, pushPayloadKey } from "@billet/contracts-push/push-payload";

const encodePayload = Schema.encodeSync(PushPayload);

/** APNs refuses a Live Activity push over 4 KB. */
export const maxPushBytes = 4096;

/** The ActivityKit attributes type the app registers. */
export const drawingActivityType = "DrawingAttributes";

const fieldsOf = (note: Note) => ({
  noteId: note.id,
  author: note.author,
  ...(note._tag === "Drawing" ? { compact: note.compact } : {}),
  ...(note._tag === "Text" ? { text: note.text } : {}),
  ...(note._tag !== "Photo" && note.paper !== undefined ? { paper: note.paper } : {}),
});

/** The server knows no names (they live on the phones); the extension may rewrite the title. */
const alertOf = (note: Note): { readonly title: string; readonly body: string } => {
  switch (note._tag) {
    case "Drawing":
      return { title: "Ourio", body: "A new drawing on your lock screen" };
    case "Photo":
      return { title: "Ourio", body: "A new photo for you" };
    case "Text":
      return { title: "Ourio", body: note.text };
  }
};

/** `mutable-content` makes the NotificationService extension open it first, to save the drawing. */
export const alertBody = (note: Note): unknown => ({
  aps: { alert: alertOf(note), sound: "default", "mutable-content": 1, "thread-id": "notes" },
  [pushPayloadKey]: encodePayload(PushPayload.cases.Alert.make(fieldsOf(note))),
});

const emoji = {
  heart: "❤️",
  laugh: "😂",
  wow: "😮",
  sad: "😢",
  fire: "🔥",
} as const satisfies Record<Reaction, string>;

/** The extension writes the partner's name into the title, as for a note. */
export const reactionAlertBody = (reaction: {
  readonly note: Note["id"];
  readonly by: Note["author"];
  readonly reaction: Reaction;
}): unknown => ({
  aps: {
    alert: { title: "Ourio", body: `${emoji[reaction.reaction]} on your photo` },
    sound: "default",
    "mutable-content": 1,
    "thread-id": "reactions",
  },
  [pushPayloadKey]: encodePayload(
    PushPayload.cases.Reaction.make({
      noteId: reaction.note,
      by: reaction.by,
      reaction: reaction.reaction,
    }),
  ),
});

/**
 * The extension writes the partner's name into the title and the streak into the App Group, so the
 * widgets show it before the app opens.
 */
export const streakAlertBody = (push: {
  readonly you: UserId;
  readonly lit: boolean;
  readonly streak: LoveStreak;
}): unknown => ({
  aps: {
    alert: {
      title: "Ourio",
      body: push.lit
        ? `Today's flame is lit: ${push.streak.days} ${push.streak.days === 1 ? "day" : "days"} in a row 🔥`
        : "Your partner did their part today. Your turn to light the flame.",
    },
    sound: "default",
    "mutable-content": 1,
    "thread-id": "streak",
  },
  [pushPayloadKey]: encodePayload(PushPayload.cases.Streak.make(push)),
});

/** No payload, so the notification extension leaves it as it is. */
export const matchAlertBody = (name: string): unknown => ({
  aps: {
    alert: { title: "It's a match!", body: `You both want to watch ${name}` },
    sound: "default",
    "thread-id": "pick-tonight",
  },
});

/** The server knows no names, and the extension leaves an alert without a payload as it is. */
export const guessAlertBody = (role: "subject" | "guesser", count: number): unknown => ({
  aps: {
    alert: {
      title: "Who knows who",
      body:
        role === "subject"
          ? `Your partner answered ${count} questions about themselves. Your turn to guess`
          : `Your partner guessed ${count} things about you. Answer to see how they did`,
    },
    sound: "default",
    "thread-id": "who-knows-who",
  },
});

/** "1st", "2nd", "3rd", "4th", "11th", "21st". */
export const ordinal = (n: number): string => {
  const tens = n % 100;
  const suffix = tens >= 11 && tens <= 13 ? "th" : (["th", "st", "nd", "rd"][n % 10] ?? "th");
  return `${n}${suffix}`;
};

const riddleAlert = (body: string): unknown => ({
  aps: {
    alert: { title: "Ourio", body },
    sound: "default",
    "thread-id": "draw-guess",
  },
});

/** The server knows no names, and the extension leaves an alert without a payload as it is. */
export const riddleAlertBody = (letters: number): unknown =>
  riddleAlert(
    `Your partner drew you a riddle. ${letters} ${letters === 1 ? "letter" : "letters"}.`,
  );

export const riddleEndedAlertBody = (word: string, solved: boolean, tries: number): unknown =>
  riddleAlert(
    solved
      ? `Your partner guessed “${word}” on the ${ordinal(tries)} try 🎉`
      : `Your partner gave up on “${word}”`,
  );

/** It only asks the widgets to reload; the payload rides along for a future reader. */
export const widgetBody = (note: Note): unknown => ({
  aps: { "content-changed": true },
  [pushPayloadKey]: encodePayload(PushPayload.cases.Widget.make(fieldsOf(note))),
});

/** Undefined for a note that is not a drawing. */
export const liveActivityBody = (note: Note, nowSeconds: number): unknown => {
  if (note._tag !== "Drawing") return undefined;
  return {
    aps: {
      timestamp: nowSeconds,
      event: "start",
      "attributes-type": drawingActivityType,
      attributes: { noteId: note.id },
      "content-state": encodePayload(
        PushPayload.cases.LiveActivity.make({
          noteId: note.id,
          author: note.author,
          compact: note.compact,
          ...(note.paper === undefined ? {} : { paper: note.paper }),
        }),
      ),
      alert: alertOf(note),
    },
  };
};

export const byteLength = (body: unknown): number =>
  new TextEncoder().encode(JSON.stringify(body)).length;
