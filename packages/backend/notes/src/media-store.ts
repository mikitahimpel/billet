import { Context, type Effect, type Option } from "effect";
import type { MediaKey } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { NotesUnavailable } from "./notes-error.ts";

/** Everything a couple has in the bucket sits under this prefix, so deleting them deletes it. */
export const mediaPrefix = (pairId: PairId): string => `pairs/${pairId}/`;

/** The private image bucket. Whoever calls it has already decided the caller may use the key. */
export class MediaStore extends Context.Service<
  MediaStore,
  {
    readonly put: (key: MediaKey, bytes: Uint8Array) => Effect.Effect<void, NotesUnavailable>;
    readonly get: (key: MediaKey) => Effect.Effect<Option.Option<Uint8Array>, NotesUnavailable>;
    readonly has: (key: MediaKey) => Effect.Effect<boolean, NotesUnavailable>;
  }
>()("@billet/backend-notes/MediaStore") {}
