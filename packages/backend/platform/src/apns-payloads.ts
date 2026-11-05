// The APNs bodies for one note on each push lane. The app's NotificationService extension reads
// the `PushPayload` beside `aps` (apps/ios/Shared/Model/Drawings.swift), and the drawing Live
// Activity decodes `content-state` as the `LiveActivity` case.
import { Schema } from "effect";
import type { Note } from "@billet/contracts-domain/note";
import type { Reaction } from "@billet/contracts-domain/reaction";
import { PushPayload, pushPayloadKey } from "@billet/contracts-push/push-payload";

const encodePayload = Schema.encodeSync(PushPayload);

/** APNs refuses a Live Activity push over 4 KB; alert and widget pushes may be 4 KB too. */
export const maxPushBytes = 4096;

/** The ActivityKit attributes type the app registers for a drawing's Live Activity. */
export const drawingActivityType = "DrawingAttributes";

const fieldsOf = (note: Note) => ({
  noteId: note.id,
  author: note.author,
  ...(note._tag === "Drawing" ? { compact: note.compact } : {}),
  ...(note._tag === "Text" ? { text: note.text } : {}),
  ...(note._tag !== "Photo" && note.paper !== undefined ? { paper: note.paper } : {}),
});

/**
 * The words on the alert. The server knows neither partner's name (they live on the phones), so
 * the title is the app's and the extension may rewrite it with the name it has.
 */
const alertOf = (note: Note): { readonly title: string; readonly body: string } => {
  switch (note._tag) {
    case "Drawing":
      return { title: "Nooki", body: "A new drawing on your lock screen" };
    case "Photo":
      return { title: "Nooki", body: "A new photo for you" };
    case "Text":
      return { title: "Nooki", body: note.text };
  }
};

/** An alert the NotificationService extension opens first (`mutable-content`), to save the drawing. */
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

/**
 * An alert to a photo's author that the partner reacted. The extension writes the partner's name
 * into the title, as for a note.
 */
export const reactionAlertBody = (reaction: {
  readonly note: Note["id"];
  readonly by: Note["author"];
  readonly reaction: Reaction;
}): unknown => ({
  aps: {
    alert: { title: "Nooki", body: `${emoji[reaction.reaction]} on your photo` },
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

/** A WidgetKit push only asks the widgets to reload; the payload rides along for a future reader. */
export const widgetBody = (note: Note): unknown => ({
  aps: { "content-changed": true },
  [pushPayloadKey]: encodePayload(PushPayload.cases.Widget.make(fieldsOf(note))),
});

/** Push-to-start for a drawing's Live Activity, or undefined for a note that is not a drawing. */
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
