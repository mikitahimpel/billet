import { Schema } from "effect";
import { IdempotencyKey } from "@billet/contracts-domain/ids";
import { describe, expect, it } from "vitest";
import { decide, isMember } from "../src/decide.ts";
import { RoomCommand } from "../src/room-command.ts";
import { RoomDecision, RoomOutput, RoomRejection } from "../src/room-decision.ts";
import { RoomState, type ActiveRoom } from "../src/room-state.ts";
import {
  active,
  alice,
  bob,
  catProfile,
  mallory,
  otherPairId,
  pairId,
  photoFrom,
  rose,
  tower,
  sea,
  textFrom,
  uuid,
  vacant,
  withCat,
  riddleOf,
} from "./samples.ts";
import { freeInk } from "@billet/contracts-domain/inks";
import { CoinEntry, CoinEntryId, EarnRef, LocalDay } from "@billet/contracts-domain/coins";
import { CollectionId, RoomItemId, starterItems } from "@billet/contracts-domain/shop";
import { ListId } from "@billet/contracts-domain/list";
import { moodNoteMaxLength } from "@billet/contracts-domain/mood";

const cozyAutumn = Schema.decodeSync(CollectionId)("cozy-autumn");

const key = Schema.decodeUnknownSync(IdempotencyKey)("6f1c2d3e-4a5b-4c6d-8e7f-0a1b2c3d4e5f");
const open = RoomCommand.cases.Open.make({ pairId, members: [alice, bob] });
const send = (author = alice) => RoomCommand.cases.SendNote.make({ note: photoFrom(author), key });
const saveCat = (user = alice, at = 1_700_000_500_000) =>
  RoomCommand.cases.SaveCat.make({
    user,
    name: catProfile.name,
    look: catProfile.look,
    utcOffsetSeconds: catProfile.utcOffsetSeconds,
    natureSeed: catProfile.natureSeed,
    at,
  });
const pet = (by = alice, at = 1_700_000_100_000, id = uuid(1)) =>
  RoomCommand.cases.RecordCatEvent.make({ id, by, at, event: { _tag: "Petted" } });
const petEntry = {
  seq: 1,
  id: uuid(1),
  by: alice,
  at: 1_700_000_100_000,
  event: { _tag: "Petted" },
} as const;
const setPresence = (user = alice, state: "idle" | "drawing" = "drawing") =>
  RoomCommand.cases.SetPresence.make({ user, state });
const heartFromBob = {
  rev: 1,
  note: photoFrom(alice).id,
  by: bob,
  at: 1_700_000_200_000,
  reaction: "heart",
} as const;
const react = (fields: Partial<Omit<RoomCommand & { _tag: "React" }, "_tag">> = {}) =>
  RoomCommand.cases.React.make({
    by: bob,
    note: photoFrom(alice),
    reaction: "heart",
    at: 1_700_000_200_000,
    ...fields,
  });
const takeBack = (fields: Parameters<typeof react>[0] = {}) => {
  const { _tag, reaction: _, ...rest } = react(fields);
  return RoomCommand.cases.React.make(rest);
};

const expectAccepted = (state: RoomState, command: RoomCommand) => {
  const decision = decide(state, command);
  if (decision._tag !== "Accepted") throw new Error(`expected Accepted, got ${decision._tag}`);
  return decision;
};
const rejection = (rejected: RoomRejection) =>
  RoomDecision.cases.Rejected.make({ rejection: rejected });

describe("decide on a vacant room", () => {
  it("opens for two different people, both idle, at sequence zero", () => {
    expect(expectAccepted(vacant, open)).toEqual({
      _tag: "Accepted",
      state: { ...active, welcomed: false },
      outputs: [RoomOutput.cases.RoomOpened.make({ pairId })],
    });
  });

  it("refuses to open for one person twice", () => {
    const command = RoomCommand.cases.Open.make({ pairId, members: [alice, alice] });
    expect(decide(vacant, command)).toEqual(
      rejection(RoomRejection.cases.DuplicateMember.make({})),
    );
  });

  it.each([
    ["SendNote", send()],
    ["SetPresence", setPresence()],
  ])("rejects %s", (_, command) => {
    expect(decide(vacant, command)).toEqual(rejection(RoomRejection.cases.RoomNotOpen.make({})));
  });
});

describe("decide on an active room", () => {
  it("treats a repeated open as a no-op, whichever way round the members are", () => {
    const repeat = RoomCommand.cases.Open.make({ pairId, members: [bob, alice] });
    expect(expectAccepted(active, open)).toEqual({ _tag: "Accepted", state: active, outputs: [] });
    expect(expectAccepted(active, repeat).state).toEqual(active);
  });

  it("refuses a repeated open that names one person twice", () => {
    const command = RoomCommand.cases.Open.make({ pairId, members: [alice, alice] });
    expect(decide(active, command)).toEqual(
      rejection(RoomRejection.cases.DuplicateMember.make({})),
    );
  });

  it.each([
    ["a different pair", { pairId: otherPairId, members: [alice, bob] as const }],
    ["a different member", { pairId, members: [alice, mallory] as const }],
  ])("rejects opening for %s", (_, fields) => {
    expect(decide(active, RoomCommand.cases.Open.make(fields))).toEqual(
      rejection(RoomRejection.cases.RoomAlreadyOpen.make({})),
    );
  });

  it("gives each note the next sequence number", () => {
    const first = expectAccepted(active, send(alice));
    const second = expectAccepted(first.state, send(bob));
    expect(first.outputs[0]).toEqual(
      RoomOutput.cases.NoteAppended.make({ entry: { seq: 1, note: photoFrom(alice) }, key }),
    );
    expect(second.outputs[0]).toEqual(
      RoomOutput.cases.NoteAppended.make({ entry: { seq: 2, note: photoFrom(bob) }, key }),
    );
    expect(second.state.lastSeq).toBe(2);
  });

  it("pays a note's reward before there is a cat", () => {
    const sent = expectAccepted(active, send(alice));
    expect(sent.outputs[1]).toEqual({
      _tag: "CoinsEntered",
      entry: {
        id: `earn:${photoFrom(alice).id}`,
        kind: "earn",
        amount: 10,
        ref: photoFrom(alice).id,
        at: photoFrom(alice).sentAt,
      },
    });
    expect(sent.state._tag === "Active" && sent.state.wallet.balance).toBe(
      active.wallet.balance + 10,
    );
  });

  it("rejects a note from outside the couple and leaves the sequence alone", () => {
    expect(decide(active, send(mallory))).toEqual(
      rejection(RoomRejection.cases.NotAMember.make({ user: mallory })),
    );
  });

  it("changes only the named member's presence", () => {
    expect(expectAccepted(active, setPresence(bob, "drawing"))).toEqual({
      _tag: "Accepted",
      state: {
        ...active,
        members: [
          { user: alice, presence: "idle" },
          { user: bob, presence: "drawing" },
        ],
      },
      outputs: [RoomOutput.cases.PresenceChanged.make({ user: bob, state: "drawing" })],
    });
  });

  it("emits nothing when presence is unchanged, so nothing is relayed", () => {
    const decision = expectAccepted(active, setPresence(alice, "idle"));
    expect(decision.outputs).toEqual([]);
    expect(decision.state).toEqual(active);
  });

  it("rejects presence from outside the couple", () => {
    expect(decide(active, setPresence(mallory))).toEqual(
      rejection(RoomRejection.cases.NotAMember.make({ user: mallory })),
    );
  });

  it("leaves the streak alone when a note is sent: the phone reports its day", () => {
    const room: ActiveRoom = { ...active, streak: { days: 3, best: 3 } };
    expect(expectAccepted(room, send()).state.streak).toEqual({ days: 3, best: 3 });
  });
});

describe("kept pieces", () => {
  const lantern = Schema.decodeSync(RoomItemId)("lantern");
  const grant = (...items: Array<typeof lantern>) => RoomCommand.cases.GrantItems.make({ items });

  it("gives the pair the pieces it lacks, once, and not the starters", () => {
    const granted = decide(active, grant(lantern, lantern, starterItems[0] as typeof lantern));
    if (granted._tag !== "Accepted") throw new Error("grant refused");
    expect(granted.state.items).toEqual([lantern]);
    expect(granted.outputs).toEqual([RoomOutput.cases.ItemsGranted.make({ items: [lantern] })]);
    const again = decide(granted.state, grant(lantern));
    expect(again).toEqual(RoomDecision.cases.Accepted.make({ state: granted.state, outputs: [] }));
  });

  it("is refused while the room is not open", () => {
    expect(decide(vacant, grant(lantern))).toEqual(
      RoomDecision.cases.Rejected.make({ rejection: RoomRejection.cases.RoomNotOpen.make({}) }),
    );
  });
});

describe("inks", () => {
  const sendText = (ink: typeof rose) =>
    RoomCommand.cases.SendNote.make({ note: textFrom(alice, ink), key });
  const grant = (...inks: Array<typeof rose>) => RoomCommand.cases.GrantInks.make({ inks });

  it("takes a text note in the free ink from any pair", () => {
    expect(decide(active, sendText(freeInk))._tag).toBe("Accepted");
  });

  it("refuses a text note in an ink the pair has not bought, and stores nothing", () => {
    expect(decide(active, sendText(rose))).toEqual(
      RoomDecision.cases.Rejected.make({
        rejection: RoomRejection.cases.InkNotOwned.make({ ink: rose }),
      }),
    );
  });

  it("takes it once the ink is granted, for either partner", () => {
    const granted = decide(active, grant(rose));
    if (granted._tag !== "Accepted") throw new Error("grant refused");
    expect(granted.state.inks).toEqual([rose]);
    expect(granted.outputs).toEqual([RoomOutput.cases.InksGranted.make({ inks: [rose] })]);
    expect(decide(granted.state, sendText(rose))._tag).toBe("Accepted");
    const fromBob = RoomCommand.cases.SendNote.make({ note: textFrom(bob, rose), key });
    expect(decide(granted.state, fromBob)._tag).toBe("Accepted");
  });

  it("grants only what is new, in order, and a repeat changes nothing", () => {
    const first = decide(active, grant(rose));
    if (first._tag !== "Accepted") throw new Error("grant refused");
    const second = decide(first.state, grant(sea, rose, sea, freeInk));
    if (second._tag !== "Accepted") throw new Error("grant refused");
    expect(second.state.inks).toEqual([rose, sea]);
    expect(second.outputs).toEqual([RoomOutput.cases.InksGranted.make({ inks: [sea] })]);
    expect(decide(second.state, grant(rose))).toEqual(
      RoomDecision.cases.Accepted.make({ state: second.state, outputs: [] }),
    );
  });

  it("needs an open room to grant", () => {
    expect(decide(vacant, grant(rose))).toEqual(
      RoomDecision.cases.Rejected.make({ rejection: RoomRejection.cases.RoomNotOpen.make({}) }),
    );
  });

  it("checks only text notes: drawings and photos have no ink", () => {
    const photo = RoomCommand.cases.SendNote.make({ note: photoFrom(alice), key });
    expect(decide(active, photo)._tag).toBe("Accepted");
  });
});

describe("reactions", () => {
  it("gives the partner's reaction to a photo the next rev", () => {
    const first = expectAccepted(active, react());
    expect(first.state.lastReactionRev).toBe(1);
    expect(first.outputs).toEqual([RoomOutput.cases.ReactionSet.make({ reaction: heartFromBob })]);
    const changed = expectAccepted(first.state, react({ current: heartFromBob, reaction: "fire" }));
    expect(changed.outputs).toEqual([
      RoomOutput.cases.ReactionSet.make({
        reaction: { ...heartFromBob, rev: 2, reaction: "fire" },
      }),
    ]);
  });

  it("takes a reaction back as a change with no reaction", () => {
    const room = { ...active, lastReactionRev: 1 };
    const { reaction: _, ...rest } = heartFromBob;
    expect(expectAccepted(room, takeBack({ current: heartFromBob })).outputs).toEqual([
      RoomOutput.cases.ReactionSet.make({ reaction: { ...rest, rev: 2 } }),
    ]);
  });

  it("answers the same reaction again with the stored one, and stores nothing", () => {
    const room = { ...active, lastReactionRev: 1 };
    expect(expectAccepted(room, react({ current: heartFromBob }))).toEqual({
      _tag: "Accepted",
      state: room,
      outputs: [RoomOutput.cases.ReactionRepeated.make({ reaction: heartFromBob })],
    });
  });

  it.each([
    ["an own photo", react({ by: alice }), RoomRejection.cases.OwnNote.make({})],
    [
      "a text note",
      react({ note: textFrom(alice, freeInk) }),
      RoomRejection.cases.NotReactable.make({}),
    ],
    [
      "someone outside the couple",
      react({ by: mallory }),
      RoomRejection.cases.NotAMember.make({ user: mallory }),
    ],
    ["taking back nothing", takeBack(), RoomRejection.cases.NoReaction.make({})],
  ])("refuses %s", (_, command, refused) => {
    expect(decide(active, command)).toEqual(rejection(refused));
  });
});

const setMood = (overrides: Partial<typeof RoomCommand.cases.SetMood.Type> = {}) =>
  RoomCommand.cases.SetMood.make({ by: bob, mood: "sleepy", at: 1_700_000_300_000, ...overrides });

describe("moods", () => {
  it("keeps a member's check-in and tells the room", () => {
    const { state, outputs } = expectAccepted(active, setMood());
    const checkIn = { user: bob, mood: "sleepy", at: 1_700_000_300_000 } as const;
    expect(state.moods).toEqual([checkIn]);
    expect(outputs).toEqual([RoomOutput.cases.MoodSet.make({ checkIn })]);
  });

  it("replaces the member's last check-in and keeps the partner's, in the members' order", () => {
    const first = expectAccepted(active, setMood({ note: "long night" }));
    const both = expectAccepted(first.state, setMood({ by: alice, mood: "missing" }));
    const replaced = expectAccepted(both.state, setMood({ mood: "happy", at: 1_700_000_400_000 }));
    expect(replaced.state.moods).toEqual([
      { user: alice, mood: "missing", at: 1_700_000_300_000 },
      { user: bob, mood: "happy", at: 1_700_000_400_000 },
    ]);
  });

  it("trims the note, and drops one that is only blanks", () => {
    expect(expectAccepted(active, setMood({ note: "  on my way  " })).state.moods).toEqual([
      { user: bob, mood: "sleepy", note: "on my way", at: 1_700_000_300_000 },
    ]);
    expect(expectAccepted(active, setMood({ note: " \n\t " })).state.moods).toEqual([
      { user: bob, mood: "sleepy", at: 1_700_000_300_000 },
    ]);
  });

  it("takes a note of exactly the limit once trimmed, and refuses a longer one", () => {
    const limit = "a".repeat(moodNoteMaxLength);
    expect(expectAccepted(active, setMood({ note: ` ${limit} ` })).state.moods[0]?.note).toBe(
      limit,
    );
    expect(decide(active, setMood({ note: `${limit}a` }))).toEqual(
      rejection(RoomRejection.cases.MoodNoteTooLong.make({})),
    );
  });

  it("refuses someone outside the couple, and a room not open yet", () => {
    expect(decide(active, setMood({ by: mallory }))).toEqual(
      rejection(RoomRejection.cases.NotAMember.make({ user: mallory })),
    );
    expect(decide(vacant, setMood())).toEqual(rejection(RoomRejection.cases.RoomNotOpen.make({})));
  });
});

describe("decide as a pure function", () => {
  it("does not mutate its input and repeats its answer", () => {
    const room = JSON.parse(JSON.stringify(active)) as ActiveRoom;
    const command = send();
    const answer = decide(room, command);
    expect(room).toEqual(active);
    expect(decide(room, command)).toEqual(answer);
  });
});

describe("isMember", () => {
  it("knows only the two partners of an active room", () => {
    expect(isMember(active, alice)).toBe(true);
    expect(isMember(active, bob)).toBe(true);
    expect(isMember(active, mallory)).toBe(false);
    expect(isMember(vacant, alice)).toBe(false);
  });
});

describe("tagged unions", () => {
  const states: Record<RoomState["_tag"], RoomState> = { Vacant: vacant, Active: withCat };
  const commands: Record<RoomCommand["_tag"], RoomCommand> = {
    Open: open,
    SendNote: send(),
    SetPresence: setPresence(),
    SaveCat: saveCat(),
    RecordCatEvent: pet(),
    GrantInks: RoomCommand.cases.GrantInks.make({ inks: [rose] }),
    GrantItems: RoomCommand.cases.GrantItems.make({
      items: [Schema.decodeSync(RoomItemId)("lantern")],
    }),
    Buy: RoomCommand.cases.Buy.make({ id: key, by: alice, ink: rose, at: 1_700_000_000_000 }),
    Order: RoomCommand.cases.Order.make({
      id: key,
      by: alice,
      offer: { _tag: "Treat" },
      at: 1_700_000_000_000,
    }),
    SetWish: RoomCommand.cases.SetWish.make({ by: alice, item: tower, wished: true }),
    React: react(),
    Welcome: RoomCommand.cases.Welcome.make({ at: 1_700_000_000_000 }),
    OpenGift: RoomCommand.cases.OpenGift.make({
      by: alice,
      at: 1_700_000_000_000,
      utcOffsetSeconds: 0,
    }),
    ClaimBonus: RoomCommand.cases.ClaimBonus.make({
      by: alice,
      at: 1_700_000_000_000,
      collection: cozyAutumn,
    }),
    Earn: RoomCommand.cases.Earn.make({
      by: alice,
      at: 1_700_000_000_000,
      utcOffsetSeconds: 0,
      event: { _tag: "ListTicked", item: Schema.decodeSync(EarnRef)("item-1") },
    }),
    ChangeList: RoomCommand.cases.ChangeList.make({
      by: alice,
      at: 1_700_000_000_000,
      utcOffsetSeconds: 0,
      change: { _tag: "DeleteList", key, list: Schema.decodeSync(ListId)(key) },
      paid: false,
    }),
    SetMood: setMood(),
    RecordStreakDay: RoomCommand.cases.RecordStreakDay.make({
      by: alice,
      at: 1_700_000_000_000,
      happenedAt: 1_699_999_000_000,
      utcOffsetSeconds: 3600,
    }),
    RestoreStreak: RoomCommand.cases.RestoreStreak.make({
      by: bob,
      at: 1_700_000_000_000,
      utcOffsetSeconds: 0,
    }),
    SaveRiddle: RoomCommand.cases.SaveRiddle.make({
      by: bob,
      at: 1_700_000_000_000,
      write: { riddle: riddleOf(alice) },
      reward: { won: true, score: 10 },
    }),
    CreditPurchase: RoomCommand.cases.CreditPurchase.make({
      id: Schema.decodeSync(CoinEntryId)("purchase:2000"),
      kind: "buy",
      coins: 550,
      ref: "com.ourio.app.coins.550",
      at: 1_700_000_000_000,
    }),
  };
  const spend = Schema.decodeUnknownSync(CoinEntry)({
    id: `spend:${key}`,
    kind: "spend",
    amount: -60,
    ref: rose,
    at: 1_700_000_000_000,
  });
  const outputs: Record<RoomOutput["_tag"], RoomOutput> = {
    RoomOpened: RoomOutput.cases.RoomOpened.make({ pairId }),
    NoteAppended: RoomOutput.cases.NoteAppended.make({
      entry: { seq: 1, note: photoFrom(alice) },
      key,
    }),
    NoteRepeated: RoomOutput.cases.NoteRepeated.make({
      entry: { seq: 1, note: photoFrom(alice) },
    }),
    PresenceChanged: RoomOutput.cases.PresenceChanged.make({ user: alice, state: "drawing" }),
    CatSaved: RoomOutput.cases.CatSaved.make({ cat: catProfile, by: alice, adopted: true }),
    CatEntryAppended: RoomOutput.cases.CatEntryAppended.make({ entry: petEntry }),
    CatEntryRepeated: RoomOutput.cases.CatEntryRepeated.make({ entry: petEntry }),
    InksGranted: RoomOutput.cases.InksGranted.make({ inks: [rose] }),
    ItemsGranted: RoomOutput.cases.ItemsGranted.make({ items: [tower] }),
    WishlistChanged: RoomOutput.cases.WishlistChanged.make({ wishlist: [tower] }),
    CoinsEntered: RoomOutput.cases.CoinsEntered.make({ entry: spend }),
    CoinsRepeated: RoomOutput.cases.CoinsRepeated.make({ entry: spend }),
    ReactionSet: RoomOutput.cases.ReactionSet.make({ reaction: heartFromBob }),
    ReactionRepeated: RoomOutput.cases.ReactionRepeated.make({ reaction: heartFromBob }),
    Purchased: RoomOutput.cases.Purchased.make({
      id: key,
      by: alice,
      at: 1_700_000_000_000,
      items: [tower],
      coins: 540,
    }),
    GiftOpened: RoomOutput.cases.GiftOpened.make({
      by: alice,
      at: 1_700_000_000_000,
      day: Schema.decodeSync(LocalDay)("2023-11-14"),
      reward: { _tag: "Coins", coins: 30 },
    }),
    BonusPaid: RoomOutput.cases.BonusPaid.make({
      by: alice,
      at: 1_700_000_000_000,
      collection: cozyAutumn,
      coins: 150,
    }),
    ListSaved: RoomOutput.cases.ListSaved.make({
      list: {
        id: Schema.decodeSync(ListId)(key),
        kind: "watch",
        title: "To watch",
        icon: { symbol: "popcorn.fill", tint: "coral" },
        items: [],
      },
      key,
      at: 1_700_000_000_000,
    }),
    ListDeleted: RoomOutput.cases.ListDeleted.make({
      list: Schema.decodeSync(ListId)(key),
      key,
      at: 1_700_000_000_000,
    }),
    ListItemAdded: RoomOutput.cases.ListItemAdded.make({
      list: Schema.decodeSync(ListId)(key),
      kind: "watch",
      title: "To watch",
      by: alice,
      slot: 0,
      at: 1_700_000_000_000,
      count: 1,
      text: "Past Lives",
    }),
    MoodSet: RoomOutput.cases.MoodSet.make({
      checkIn: { user: bob, mood: "busy", note: "deadline", at: 1_700_000_000_000 },
    }),
    RiddleSaved: RoomOutput.cases.RiddleSaved.make({ write: { riddle: riddleOf(alice) } }),
    StreakChanged: RoomOutput.cases.StreakChanged.make({
      streak: { days: 3, best: 5, lastDay: Schema.decodeSync(LocalDay)("2023-11-14") },
      by: alice,
      at: 1_700_000_000_000,
      reached: 3,
    }),
  };
  const rejections: Record<RoomRejection["_tag"], RoomRejection> = {
    DuplicateMember: RoomRejection.cases.DuplicateMember.make({}),
    RoomNotOpen: RoomRejection.cases.RoomNotOpen.make({}),
    RoomAlreadyOpen: RoomRejection.cases.RoomAlreadyOpen.make({}),
    NotAMember: RoomRejection.cases.NotAMember.make({ user: mallory }),
    CatNotAdopted: RoomRejection.cases.CatNotAdopted.make({}),
    CatEntryIdTaken: RoomRejection.cases.CatEntryIdTaken.make({}),
    InkNotOwned: RoomRejection.cases.InkNotOwned.make({ ink: rose }),
    NotEnoughCoins: RoomRejection.cases.NotEnoughCoins.make({ needed: 60, have: 5 }),
    PriceChanged: RoomRejection.cases.PriceChanged.make({ price: 560 }),
    AlreadyOwned: RoomRejection.cases.AlreadyOwned.make({ ink: rose }),
    NotSold: RoomRejection.cases.NotSold.make({ ink: rose }),
    OfferOwned: RoomRejection.cases.OfferOwned.make({ offer: tower }),
    NotOffered: RoomRejection.cases.NotOffered.make({}),
    NoteNotFound: RoomRejection.cases.NoteNotFound.make({}),
    OwnNote: RoomRejection.cases.OwnNote.make({}),
    NotReactable: RoomRejection.cases.NotReactable.make({}),
    NoReaction: RoomRejection.cases.NoReaction.make({}),
    GiftTaken: RoomRejection.cases.GiftTaken.make({
      day: Schema.decodeSync(LocalDay)("2023-11-14"),
    }),
    CollectionIncomplete: RoomRejection.cases.CollectionIncomplete.make({ collection: cozyAutumn }),
    BonusTaken: RoomRejection.cases.BonusTaken.make({ collection: cozyAutumn }),
    ListNotFound: RoomRejection.cases.ListNotFound.make({}),
    ListItemNotFound: RoomRejection.cases.ListItemNotFound.make({}),
    MoodNoteTooLong: RoomRejection.cases.MoodNoteTooLong.make({}),
    RoomJournalsGame: RoomRejection.cases.RoomJournalsGame.make({}),
    StreakNotRestorable: RoomRejection.cases.StreakNotRestorable.make({}),
  };

  it.each([
    ["RoomState", RoomState, states],
    ["RoomCommand", RoomCommand, commands],
    ["RoomOutput", RoomOutput, outputs],
    ["RoomRejection", RoomRejection, rejections],
  ] as const)("%s has a sample for every case, and each one round-trips", (_, union, samples) => {
    expect(Object.keys(samples).toSorted()).toEqual(Object.keys(union.cases).toSorted());
    for (const [tag, sample] of Object.entries(samples)) {
      expect((sample as { _tag: string })._tag).toBe(tag);
      const schema = union as unknown as Schema.Codec<unknown, unknown>;
      const encoded = Schema.encodeUnknownSync(schema)(sample);
      expect(Schema.decodeUnknownSync(schema)(encoded)).toEqual(sample);
    }
  });

  it("every command has an answer in every state", () => {
    for (const state of Object.values(states)) {
      for (const command of Object.values(commands)) {
        expect(Object.keys(RoomDecision.cases)).toContain(decide(state, command)._tag);
      }
    }
  });

  it("rejects untagged input at the schema boundary", () => {
    expect(() =>
      Schema.decodeUnknownSync(RoomCommand)({ pairId, members: [alice, bob] }),
    ).toThrow();
    expect(() => Schema.decodeUnknownSync(RoomState)({ lastSeq: 0 })).toThrow();
  });
});

describe("RoomState invariants", () => {
  const member = (user: typeof alice) => ({ user, presence: "idle" as const });
  const make = (overrides: Record<string, unknown>) =>
    Schema.decodeUnknownSync(RoomState)({
      _tag: "Active",
      pairId,
      members: [member(alice), member(bob)],
      lastSeq: 0,
      streak: { days: 0, best: 0 },
      inks: [],
      items: [],
      wishlist: [],
      wallet: { balance: 0, care: 0, notes: 0, games: 0 },
      ...overrides,
    });

  it("accepts a valid room", () => {
    expect(make({})).toMatchObject({ _tag: "Active", lastSeq: 0 });
  });

  it.each([
    ["the same user twice", { members: [member(alice), member(alice)] }],
    ["a negative lastSeq", { lastSeq: -1 }],
    ["a negative streak", { streak: { days: -1, best: 0 } }],
    ["an ink that is not an ink id", { inks: ["rose"] }],
    ["a piece that is not a piece id", { items: ["Lamp"] }],
  ])("rejects %s", (_, overrides) => {
    expect(() => make(overrides)).toThrow();
  });
});
