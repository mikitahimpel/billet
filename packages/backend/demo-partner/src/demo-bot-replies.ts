import { Schema } from "effect";
import { NoteText } from "@billet/contracts-domain/note";

/** What the demo bot answers a text note with. Each must pass as a note's words. */
export const demoBotReplies = Schema.decodeSync(Schema.NonEmptyArray(NoteText))([
  "aww, you made me smile",
  "thinking of you too",
  "miss you already",
  "that's so sweet",
  "hehe, love that",
  "you're the best",
  "can't wait to see you",
  "sending you a big hug",
  "this made my day",
  "same here, always",
  "you always know what to say",
  "the cat says hi too",
  "counting the hours",
  "ok now I'm blushing",
  "tell me more later?",
  "you + me = favourite",
  "saving this one forever",
  "hope your day is gentle",
  "drink some water, cutie",
  "goodnight thoughts already",
]);
