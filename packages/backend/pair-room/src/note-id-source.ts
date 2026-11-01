import { Context, type Effect } from "effect";
import type { NoteId } from "@billet/contracts-domain/ids";

/** Where new note ids come from, injected so this package needs no runtime globals. */
export class NoteIdSource extends Context.Service<
  NoteIdSource,
  { readonly next: Effect.Effect<NoteId> }
>()("@billet/backend-pair-room/NoteIdSource") {}
