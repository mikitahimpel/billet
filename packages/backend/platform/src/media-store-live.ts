import { Effect, Layer, Option, Schema } from "effect";
import { MediaKey } from "@billet/contracts-domain/ids";
import { MediaStore, mediaPrefix } from "@billet/backend-notes/media-store";
import { NotesUnavailable } from "@billet/backend-notes/notes-error";

// A storage error can quote the key, so nothing from it survives this label.
const guarded = <A>(run: () => Promise<A>) =>
  Effect.tryPromise({
    try: run,
    catch: () => new NotesUnavailable({ reason: "media-unavailable" }),
  });

const decodeKey = Schema.decodeUnknownOption(MediaKey);

/** R2 deletes at most this many keys in one call. */
const deleteBatch = 1000;

/**
 * `MediaStore` on the private R2 bucket. Each image carries its uploader's id as custom metadata,
 * so deleting an account finds the images it uploaded and never sent. Images stored before that
 * have none; a sent one is still found through its note.
 */
export const MediaStoreLive = (bucket: R2Bucket): Layer.Layer<MediaStore> =>
  Layer.succeed(
    MediaStore,
    MediaStore.of({
      put: (key, bytes, uploader) =>
        guarded(() =>
          bucket.put(key, bytes, {
            httpMetadata: { contentType: "image/png" },
            customMetadata: { uploader },
          }),
        ).pipe(Effect.asVoid),
      get: (key) =>
        guarded(async () => {
          const object = await bucket.get(key);
          return object === null
            ? Option.none<Uint8Array>()
            : Option.some(new Uint8Array(await object.arrayBuffer()));
        }),
      has: (key) => guarded(() => bucket.head(key)).pipe(Effect.map((object) => object !== null)),
      uploadedBy: (pairId, uploader) =>
        guarded(async () => {
          const keys: MediaKey[] = [];
          let cursor: string | undefined;
          do {
            const page = await bucket.list({
              prefix: mediaPrefix(pairId),
              include: ["customMetadata"],
              ...(cursor === undefined ? {} : { cursor }),
            });
            for (const object of page.objects) {
              if (object.customMetadata?.["uploader"] !== uploader) continue;
              const key = decodeKey(object.key);
              if (Option.isSome(key)) keys.push(key.value);
            }
            cursor = page.truncated ? page.cursor : undefined;
          } while (cursor !== undefined);
          return keys;
        }),
      remove: (keys) =>
        guarded(async () => {
          for (let start = 0; start < keys.length; start += deleteBatch) {
            await bucket.delete(keys.slice(start, start + deleteBatch));
          }
        }),
    }),
  );
