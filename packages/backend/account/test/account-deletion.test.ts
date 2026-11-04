import { Effect, Exit, Layer, Option, Redacted, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { IdempotencyKey, MediaKey, type UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import { SendNoteRequest } from "@billet/contracts-http-api/note";
import { NotesUnavailable } from "@billet/backend-notes/notes-error";
import { NotesService } from "@billet/backend-notes/notes-service";
import { PairRooms } from "@billet/backend-notes/pair-rooms";
import { makeWorld, pair, user } from "@billet/backend-notes/test/fake-world";
import { AccountDeletion } from "../src/account-deletion.ts";
import { AccountUnavailable } from "../src/account-error.ts";
import { AccountRepository, type Erasure } from "../src/account-repository.ts";
import { AppleTokenRevoker } from "../src/apple-token-revoker.ts";
import { plainExit } from "@billet/backend-observability/test/plain-exit";

const ana = user("ana");
const ben = user("ben");
const now = pair("pair-now");
const before = pair("pair-before");

const png = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0xff]);

let keyCount = 0;
const newKey = () =>
  Schema.decodeSync(IdempotencyKey)(
    `00000000-0000-4000-8000-${String((keyCount += 1)).padStart(12, "0")}`,
  );

/** The notes world with Ana and Ben paired, and Ana's earlier pair still holding her notes. */
const setup = (options: { readonly pairs?: ReadonlyArray<PairId> } = {}) => {
  const world = makeWorld([[now, ana, ben]]);
  const erased: Array<Erasure> = [];
  const revoked: Array<string> = [];
  const repository = Layer.succeed(AccountRepository, {
    pairsOf: () => Effect.succeed(options.pairs ?? [now]),
    erase: (erasure) => Effect.sync(() => void erased.push(erasure)),
  });
  const revoker = Layer.succeed(AppleTokenRevoker, {
    revoke: (code) => Effect.sync(() => (revoked.push(Redacted.value(code)), "revoked" as const)),
  });
  const deletion = (rooms?: Partial<PairRooms["Service"]>) =>
    AccountDeletion.layer.pipe(
      Layer.provide(
        Layer.mergeAll(
          world.layer,
          Layer.succeed(PairRooms, { ...world.pairRooms, ...rooms }),
          repository,
          revoker,
        ),
      ),
    );
  const notes = NotesService.layer.pipe(Layer.provide(world.layer));

  const send = (author: UserId) =>
    NotesService.use((service) =>
      Effect.gen(function* () {
        const image = yield* service.uploadImage(author, png);
        yield* service.sendNote(author, SendNoteRequest.cases.Photo.make({ key: newKey(), image }));
        return image;
      }),
    ).pipe(Effect.provide(notes), Effect.runPromise);
  const upload = (author: UserId) =>
    NotesService.use((service) => service.uploadImage(author, png)).pipe(
      Effect.provide(notes),
      Effect.runPromise,
    );
  const history = (reader: UserId) =>
    NotesService.use((service) => service.history(reader, 0, 100)).pipe(
      Effect.provide(notes),
      Effect.runPromise,
    );
  const run = (
    code: Option.Option<string>,
    rooms?: Partial<PairRooms["Service"]>,
  ): Promise<Exit.Exit<void, AccountUnavailable>> =>
    AccountDeletion.use((service) => service.deleteAccount(ana, Option.map(code, Redacted.make)))
      .pipe(Effect.provide(deletion(rooms)), Effect.runPromiseExit)
      .then(plainExit);

  return { world, erased, revoked, send, upload, history, run };
};

describe("AccountDeletion", () => {
  it("deletes the user's notes and images, keeps the partner's, and tells the partner", async () => {
    const { world, erased, send, upload, history, run } = setup();
    const anaSent = await send(ana);
    const benSent = await send(ben);
    const anaUnsent = await upload(ana);

    expect(await run(Option.none())).toEqual(Exit.void);

    expect([...world.objects.keys()]).toEqual([benSent]);
    expect(world.objects.has(anaSent)).toBe(false);
    expect(world.objects.has(anaUnsent)).toBe(false);
    expect((await history(ben)).map(({ note }) => note.author)).toEqual([ben]);
    expect(erased).toEqual([{ userId: ana, partner: Option.some(ben), at: expect.any(Number) }]);
  });

  it("clears the rooms of pairs the user has left as well", async () => {
    const { world, erased, run } = setup({ pairs: [now, before] });
    const image = Schema.decodeSync(MediaKey)(`pairs/${before}/notes/old.png`);
    await Effect.runPromise(
      Effect.gen(function* () {
        yield* world.pairRooms.open(before, [ana, user("cal")]);
        yield* world.media.put(image, png, ana);
        yield* world.pairRooms.sendNote(
          before,
          ana,
          SendNoteRequest.cases.Photo.make({ key: newKey(), image }),
        );
      }),
    );

    expect(await run(Option.none())).toEqual(Exit.void);
    expect(world.objects.has(image)).toBe(false);
    const left = await Effect.runPromise(world.pairRooms.notesAfter(before, 0, 100));
    expect(left).toEqual([]);
    expect(erased).toHaveLength(1);
  });

  it("revokes the Apple token when the app sends a code, before deleting", async () => {
    const { revoked, erased, run } = setup();
    expect(await run(Option.some("apple-code"))).toEqual(Exit.void);
    expect(revoked).toEqual(["apple-code"]);
    expect(erased).toHaveLength(1);
  });

  it("revokes nothing without a code", async () => {
    const { revoked, run } = setup();
    await run(Option.none());
    expect(revoked).toEqual([]);
  });

  it("keeps the account when a room can't be cleared, so the app can try again", async () => {
    const { erased, run } = setup();
    const exit = await run(Option.none(), {
      forgetMember: () => Effect.fail(new NotesUnavailable({ reason: "room-unavailable" })),
    });
    expect(exit).toEqual(Exit.fail(new AccountUnavailable({ reason: "notes-unavailable" })));
    expect(erased).toEqual([]);
  });

  it("erases an unpaired user without a partner to tell", async () => {
    const world = makeWorld([]);
    const erased: Array<Erasure> = [];
    const exit = await AccountDeletion.use((service) =>
      service.deleteAccount(ana, Option.none()),
    ).pipe(
      Effect.provide(
        AccountDeletion.layer.pipe(
          Layer.provide(
            Layer.mergeAll(
              world.layer,
              Layer.succeed(AccountRepository, {
                pairsOf: () => Effect.succeed([]),
                erase: (erasure) => Effect.sync(() => void erased.push(erasure)),
              }),
              AppleTokenRevoker.unconfigured,
            ),
          ),
        ),
      ),
      Effect.runPromiseExit,
    );
    expect(exit).toEqual(Exit.void);
    expect(erased).toEqual([{ userId: ana, partner: Option.none(), at: expect.any(Number) }]);
  });
});
