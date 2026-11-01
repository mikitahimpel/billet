import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { decide, isMember } from "../src/decide.ts";
import { RoomCommand } from "../src/room-command.ts";
import { RoomDecision, RoomOutput, RoomRejection } from "../src/room-decision.ts";
import { RoomState, type ActiveRoom } from "../src/room-state.ts";
import { active, alice, bob, mallory, otherPairId, pairId, photoFrom, vacant } from "./samples.ts";

const open = RoomCommand.cases.Open.make({ pairId, members: [alice, bob] });
const send = (author = alice) => RoomCommand.cases.SendNote.make({ note: photoFrom(author) });
const setPresence = (user = alice, state: "idle" | "drawing" = "drawing") =>
  RoomCommand.cases.SetPresence.make({ user, state });

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
      state: active,
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
    expect(first.outputs).toEqual([
      RoomOutput.cases.NoteAppended.make({ entry: { seq: 1, note: photoFrom(alice) } }),
    ]);
    expect(second.outputs).toEqual([
      RoomOutput.cases.NoteAppended.make({ entry: { seq: 2, note: photoFrom(bob) } }),
    ]);
    expect(second.state.lastSeq).toBe(2);
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

  it("leaves the streak alone until #20 gives it rules", () => {
    const room: ActiveRoom = { ...active, streakDays: 3 };
    expect(expectAccepted(room, send()).state.streakDays).toBe(3);
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
  const states: Record<RoomState["_tag"], RoomState> = { Vacant: vacant, Active: active };
  const commands: Record<RoomCommand["_tag"], RoomCommand> = {
    Open: open,
    SendNote: send(),
    SetPresence: setPresence(),
  };
  const outputs: Record<RoomOutput["_tag"], RoomOutput> = {
    RoomOpened: RoomOutput.cases.RoomOpened.make({ pairId }),
    NoteAppended: RoomOutput.cases.NoteAppended.make({
      entry: { seq: 1, note: photoFrom(alice) },
    }),
    PresenceChanged: RoomOutput.cases.PresenceChanged.make({ user: alice, state: "drawing" }),
  };
  const rejections: Record<RoomRejection["_tag"], RoomRejection> = {
    DuplicateMember: RoomRejection.cases.DuplicateMember.make({}),
    RoomNotOpen: RoomRejection.cases.RoomNotOpen.make({}),
    RoomAlreadyOpen: RoomRejection.cases.RoomAlreadyOpen.make({}),
    NotAMember: RoomRejection.cases.NotAMember.make({ user: mallory }),
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
