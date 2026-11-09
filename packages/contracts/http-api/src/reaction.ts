import { Schema } from "effect";
import { NoteId } from "@billet/contracts-domain/ids";
import { NoteReaction, Reaction } from "@billet/contracts-domain/reaction";

/** Takes the caller's reaction back when `reaction` is absent. */
export const ReactRequest = Schema.Struct({
  note: NoteId,
  reaction: Schema.optionalKey(Reaction),
});
export type ReactRequest = typeof ReactRequest.Type;

export const ReactResponse = Schema.Struct({ reaction: NoteReaction });
export type ReactResponse = typeof ReactResponse.Type;

/** Oldest first. The next page starts after the last one's `rev`. */
export const ListReactionsResponse = Schema.Struct({ reactions: Schema.Array(NoteReaction) });
export type ListReactionsResponse = typeof ListReactionsResponse.Type;
