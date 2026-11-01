import { Effect, Layer, Option } from "effect";
import { MediaStore } from "@billet/backend-notes/media-store";
import { NotesUnavailable } from "@billet/backend-notes/notes-error";

// A storage error can quote the key, so nothing from it survives this label.
const guarded = <A>(run: () => Promise<A>) =>
  Effect.tryPromise({
    try: run,
    catch: () => new NotesUnavailable({ reason: "media-unavailable" }),
  });

/** `MediaStore` on the private R2 bucket. */
export const MediaStoreLive = (bucket: R2Bucket): Layer.Layer<MediaStore> =>
  Layer.succeed(
    MediaStore,
    MediaStore.of({
      put: (key, bytes) =>
        guarded(() => bucket.put(key, bytes, { httpMetadata: { contentType: "image/png" } })).pipe(
          Effect.asVoid,
        ),
      get: (key) =>
        guarded(async () => {
          const object = await bucket.get(key);
          return object === null
            ? Option.none<Uint8Array>()
            : Option.some(new Uint8Array(await object.arrayBuffer()));
        }),
      has: (key) => guarded(() => bucket.head(key)).pipe(Effect.map((object) => object !== null)),
    }),
  );
