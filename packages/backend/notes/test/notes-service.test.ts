import { Effect, Exit, Layer, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { IdempotencyKey, MediaKey, type UserId } from "@billet/contracts-domain/ids";
import type { CompactStrokes } from "@billet/contracts-domain/ink";
import { SendNoteRequest } from "@billet/contracts-http-api/note";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { PairingUnavailable } from "@billet/backend-pairing/pairing-error";
import { MediaStore, mediaPrefix } from "../src/media-store.ts";
import { InvalidNote, NotesNotFound, NotesUnavailable } from "../src/notes-error.ts";
import { compactBudget, NotesService } from "../src/notes-service.ts";
import { PairRooms } from "../src/pair-rooms.ts";
import { makeWorld, pair, user } from "./fake-world.ts";

const ana = user("ana");
const ben = user("ben");
const cal = user("cal");
const dee = user("dee");
const eve = user("eve");
const pairA = pair("pair-a");
const pairB = pair("pair-b");

const png = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0xff]);

const world = () =>
  makeWorld([
    [pairA, ana, ben],
    [pairB, cal, dee],
  ]);

const run = <A, E>(
  layer: ReturnType<typeof world>["layer"],
  use: (notes: NotesService["Service"]) => Effect.Effect<A, E>,
) =>
  Effect.runPromise(
    Effect.exit(
      NotesService.use(use).pipe(Effect.provide(NotesService.layer.pipe(Layer.provide(layer)))),
    ),
  );

const failed = (error: unknown) => Exit.fail(error);

let keyCount = 0;
/** A new key each time, so repeated sends are different notes unless a test reuses a key. */
const newKey = () =>
  Schema.decodeSync(IdempotencyKey)(
    `00000000-0000-4000-8000-${String((keyCount += 1)).padStart(12, "0")}`,
  );

const photo = (image: MediaKey) => SendNoteRequest.cases.Photo.make({ key: newKey(), image });

/** Fills up with one-digit points, four bytes a pair, then makes up the rest in the width's digits. */
const compactOfSize = (size: number): CompactStrokes => {
  const compactWith = (width: number, points: ReadonlyArray<number>): CompactStrokes => ({
    version: 1,
    strokes: [{ color: "#000000", width, points }],
  });
  const length = (compact: CompactStrokes) => JSON.stringify(compact).length;
  const pairs = Math.floor((size - length(compactWith(1, [])) + 1) / 4);
  const points = Array.from({ length: 2 * pairs }, () => 1);
  return compactWith(10 ** (size - length(compactWith(1, points))), points);
};

describe("uploadImage", () => {
  it("stores the bytes under the couple's prefix", async () => {
    const { layer, objects } = world();
    const key = await Effect.runPromise(
      NotesService.use((notes) => notes.uploadImage(ana, png)).pipe(
        Effect.provide(NotesService.layer.pipe(Layer.provide(layer))),
      ),
    );
    expect(key.startsWith(mediaPrefix(pairA))).toBe(true);
    expect(objects.get(key)).toEqual(png);
  });

  it.each([
    ["empty", new Uint8Array()],
    ["too short for a signature", png.slice(0, 7)],
    ["some other format", Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0, 0])],
  ])("refuses bytes that are %s", async (_, bytes) => {
    const { layer, objects } = world();
    expect(await run(layer, (notes) => notes.uploadImage(ana, bytes))).toEqual(
      failed(new InvalidNote()),
    );
    expect(objects.size).toBe(0);
  });

  it("refuses a user with no partner", async () => {
    const { layer, objects } = world();
    expect(await run(layer, (notes) => notes.uploadImage(eve, png))).toEqual(
      failed(new NotesNotFound()),
    );
    expect(objects.size).toBe(0);
  });
});

describe("readImage", () => {
  it("gives the partner the bytes, and nobody else", async () => {
    const { layer } = world();
    const read = (reader: UserId) =>
      run(layer, (notes) =>
        notes.uploadImage(ana, png).pipe(Effect.flatMap((key) => notes.readImage(reader, key))),
      );
    expect(await read(ben)).toEqual(Exit.succeed(png));
    expect(await read(cal)).toEqual(failed(new NotesNotFound()));
    expect(await read(eve)).toEqual(failed(new NotesNotFound()));
  });

  it("never asks the bucket about another couple's key", async () => {
    const { layer, media } = world();
    const forbidden = Effect.die("the bucket was read");
    const guarded = Layer.merge(
      layer,
      Layer.succeed(MediaStore, { ...media, get: () => forbidden, has: () => forbidden }),
    );
    const key = Schema.decodeSync(MediaKey)(`${mediaPrefix(pairB)}notes/1.png`);
    expect(await run(guarded, (notes) => notes.readImage(ana, key))).toEqual(
      failed(new NotesNotFound()),
    );
  });

  it("does not treat a pair id that only starts the same as the same prefix", async () => {
    const { layer } = world();
    const key = Schema.decodeSync(MediaKey)(`${mediaPrefix(pairA).slice(0, -1)}-2/notes/1.png`);
    expect(await run(layer, (notes) => notes.readImage(ana, key))).toEqual(
      failed(new NotesNotFound()),
    );
  });
});

describe("sendNote", () => {
  it("returns the first note for a key sent again, and stores it once", async () => {
    const { layer } = world();
    const outcome = await run(layer, (notes) =>
      Effect.gen(function* () {
        const image = yield* notes.uploadImage(ana, png);
        const request = photo(image);
        const first = yield* notes.sendNote(ana, request);
        const again = yield* notes.sendNote(ana, request);
        return { first, again, history: yield* notes.history(ana, 0, 10) };
      }),
    );
    expect(Exit.isSuccess(outcome)).toBe(true);
    if (Exit.isSuccess(outcome)) {
      expect(outcome.value.again).toEqual(outcome.value.first);
      expect(outcome.value.history).toEqual([{ seq: 1, note: outcome.value.first }]);
    }
  });

  const sendTwice = (notes: NotesService["Service"]) =>
    Effect.gen(function* () {
      const image = yield* notes.uploadImage(ana, png);
      const first = yield* notes.sendNote(ana, photo(image));
      const second = yield* notes.sendNote(ben, photo(image));
      return { first, second, history: yield* notes.history(ben, 0, 10) };
    });

  it("opens the room on the first note, then appends in order", async () => {
    const { layer } = world();
    const exit = await run(layer, sendTwice);
    expect(Exit.isSuccess(exit)).toBe(true);
    if (Exit.isSuccess(exit)) {
      const { first, second, history } = exit.value;
      expect(history).toEqual([
        { seq: 1, note: first },
        { seq: 2, note: second },
      ]);
      expect([first.author, second.author]).toEqual([ana, ben]);
    }
  });

  it("refuses an image outside the couple's prefix, or one never uploaded", async () => {
    const { layer } = world();
    const outcome = await run(layer, (notes) =>
      Effect.gen(function* () {
        const theirs = yield* notes.uploadImage(cal, png);
        const ghost = Schema.decodeSync(MediaKey)(`${mediaPrefix(pairA)}notes/ghost.png`);
        return [
          yield* Effect.exit(notes.sendNote(ana, photo(theirs))),
          yield* Effect.exit(notes.sendNote(ana, photo(ghost))),
          yield* notes.history(ana, 0, 10),
        ];
      }),
    );
    expect(outcome).toEqual(
      Exit.succeed([failed(new NotesNotFound()), failed(new NotesNotFound()), []]),
    );
  });

  it("takes a compact rendition at the budget and refuses one byte more", async () => {
    const { layer } = world();
    const send = (size: number) =>
      run(layer, (notes) =>
        notes.uploadImage(ana, png).pipe(
          Effect.flatMap((image) =>
            notes.sendNote(
              ana,
              SendNoteRequest.cases.Drawing.make({
                key: newKey(),
                image,
                compact: compactOfSize(size),
              }),
            ),
          ),
        ),
      );
    expect(JSON.stringify(compactOfSize(compactBudget))).toHaveLength(compactBudget);
    expect(Exit.isSuccess(await send(compactBudget))).toBe(true);
    expect(await send(compactBudget + 1)).toEqual(failed(new InvalidNote()));
  });

  it("is unavailable, not lost, when the room refuses after opening", async () => {
    const { layer, pairRooms } = world();
    const refusing = Layer.merge(
      layer,
      Layer.succeed(PairRooms, {
        ...pairRooms,
        open: () => Effect.die("the room is already open"),
        sendNote: () =>
          Effect.succeed({
            _tag: "Rejected" as const,
            rejection: { _tag: "NotAMember" as const, user: ana },
          }),
      }),
    );
    const outcome = await run(refusing, (notes) =>
      notes.uploadImage(ana, png).pipe(Effect.flatMap((key) => notes.sendNote(ana, photo(key)))),
    );
    expect(outcome).toEqual(failed(new NotesUnavailable({ reason: "room-refused-note" })));
  });

  it("does not open a room for a pair that ended while the note was on its way", async () => {
    const { layer, repository, media } = world();
    const ended = Layer.mergeAll(
      layer,
      Layer.succeed(PairingRepository, {
        ...repository,
        findMembers: () => Effect.succeed([]),
      }),
      Layer.succeed(MediaStore, media),
    );
    const outcome = await run(ended, (notes) =>
      notes.uploadImage(ana, png).pipe(Effect.flatMap((key) => notes.sendNote(ana, photo(key)))),
    );
    expect(outcome).toEqual(failed(new NotesNotFound()));
  });
});

describe("metrics", () => {
  const sendOnce = (
    notes: NotesService["Service"],
    author: typeof ana,
    request?: SendNoteRequest,
  ) =>
    notes
      .uploadImage(author, png)
      .pipe(Effect.flatMap((image) => notes.sendNote(author, request ?? photo(image))));

  it("counts a stored note once, for its author and pair, with a name and no content", async () => {
    const { layer, recorded } = world();
    await run(layer, (notes) => sendOnce(notes, ana));
    expect(recorded).toEqual([{ userId: ana, pairId: pairA, name: "NoteSent" }]);
  });

  it("counts nothing for a note that was refused", async () => {
    const { layer, recorded } = world();
    await run(layer, (notes) =>
      notes.sendNote(
        ana,
        photo(Schema.decodeSync(MediaKey)(`${mediaPrefix(pairA)}notes/ghost.png`)),
      ),
    );
    expect(recorded).toEqual([]);
  });

  it("counts a send repeated under one key once", async () => {
    const { layer, recorded } = world();
    await run(layer, (notes) =>
      Effect.gen(function* () {
        const image = yield* notes.uploadImage(ana, png);
        const request = photo(image);
        yield* notes.sendNote(ana, request);
        yield* notes.sendNote(ana, request);
        yield* notes.sendNote(ana, request);
      }),
    );
    expect(recorded).toHaveLength(1);
  });

  it("counts each partner's notes under their own name", async () => {
    const { layer, recorded } = world();
    await run(layer, (notes) =>
      Effect.gen(function* () {
        yield* sendOnce(notes, ana);
        yield* sendOnce(notes, ben);
        yield* sendOnce(notes, ana);
      }),
    );
    expect(recorded.map(({ userId }) => userId)).toEqual([ana, ben, ana]);
  });
});

describe("history", () => {
  it("is empty for a couple who haven't sent anything", async () => {
    const { layer } = world();
    expect(await run(layer, (notes) => notes.history(ana, 0, 10))).toEqual(Exit.succeed([]));
  });

  it("refuses a user with no partner", async () => {
    const { layer } = world();
    expect(await run(layer, (notes) => notes.history(eve, 0, 10))).toEqual(
      failed(new NotesNotFound()),
    );
  });

  it("is unavailable when the directory can't be read", async () => {
    const { layer, repository } = world();
    const down = Layer.merge(
      layer,
      Layer.succeed(PairingRepository, {
        ...repository,
        findPair: () => Effect.fail(new PairingUnavailable({ reason: "directory-unavailable" })),
      }),
    );
    expect(await run(down, (notes) => notes.history(ana, 0, 10))).toEqual(
      failed(new NotesUnavailable({ reason: "directory-unavailable" })),
    );
  });
});
