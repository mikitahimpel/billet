import { Effect, Layer, Option, Schema } from "effect";
import { MediaKey } from "@billet/contracts-domain/ids";
import { contentTypeOf } from "@billet/backend-notes/image-type";
import { MediaStore, mediaPrefix } from "@billet/backend-notes/media-store";
import { NotesUnavailable } from "@billet/backend-notes/notes-error";
import { spanMethods } from "@billet/backend-observability/span-methods";

// A storage error can quote the key, so nothing from it survives this label.
const guarded = <A>(run: () => Promise<A>) =>
  Effect.tryPromise({
    try: run,
    catch: (cause) => new NotesUnavailable({ reason: "media-unavailable", cause }),
  });

const decodeKey = Schema.decodeUnknownOption(MediaKey);

/** R2 deletes at most this many keys in one call. */
const deleteBatch = 1000;

/**
 * The uploader's id rides as metadata so account deletion finds unsent images; older ones lack it.
 */
export const MediaStoreLive = (bucket: R2Bucket): Layer.Layer<MediaStore> =>
  Layer.succeed(
    MediaStore,
    MediaStore.of(
      spanMethods("MediaStore", {
        put: (key, bytes, uploader) =>
          guarded(() =>
            bucket.put(key, bytes, {
              httpMetadata: { contentType: contentTypeOf(key) },
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
        removeAll: (pairId) =>
          guarded(async () => {
            let cursor: string | undefined;
            do {
              const page = await bucket.list({
                prefix: mediaPrefix(pairId),
                ...(cursor === undefined ? {} : { cursor }),
              });
              const keys = page.objects.map(({ key }) => key);
              for (let start = 0; start < keys.length; start += deleteBatch) {
                await bucket.delete(keys.slice(start, start + deleteBatch));
              }
              cursor = page.truncated ? page.cursor : undefined;
            } while (cursor !== undefined);
          }),
        remove: (keys) =>
          guarded(async () => {
            for (let start = 0; start < keys.length; start += deleteBatch) {
              await bucket.delete(keys.slice(start, start + deleteBatch));
            }
          }),
      }),
    ),
  );
