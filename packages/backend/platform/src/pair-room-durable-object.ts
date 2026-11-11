import { DurableObject } from "cloudflare:workers";
import { getTableName, is } from "drizzle-orm";
import { SQLiteTable } from "drizzle-orm/sqlite-core";
import { Clock, Effect, Layer, ManagedRuntime, Schema, Scope } from "effect";
import { type CoinEntryId, type EarnEvent, LocalDay } from "@billet/contracts-domain/coins";
import { type IdempotencyKey, UserId } from "@billet/contracts-domain/ids";
import type { InkId } from "@billet/contracts-domain/inks";
import type { PriceTerms } from "@billet/contracts-domain/shop-catalog";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { LayoutChange } from "@billet/contracts-domain/decor";
import type { CollectionId, RoomItemId, ShopOffer } from "@billet/contracts-domain/shop";
import type { ActivityCursor } from "@billet/contracts-domain/activity";
import type { CatEntry, NatureSeed } from "@billet/contracts-domain/cat";
import type { ActivityResponse } from "@billet/contracts-http-api/activity";
import type { CoinsResponse } from "@billet/contracts-http-api/coins";
import type { ShopResponse } from "@billet/contracts-http-api/shop";
import type {
  CatResponse,
  RecordCatEventRequest,
  SaveCatRequest,
} from "@billet/contracts-http-api/cat";
import type { SendNoteRequest } from "@billet/contracts-http-api/note";
import type { ReactRequest } from "@billet/contracts-http-api/reaction";
import type { NoteReaction } from "@billet/contracts-domain/reaction";
import type { MoodCheckIn } from "@billet/contracts-domain/mood";
import type { SetMoodRequest } from "@billet/contracts-http-api/mood";
import type { LoveStreak } from "@billet/contracts-domain/streak";
import type {
  RecordStreakDayRequest,
  RestoreStreakRequest,
} from "@billet/contracts-http-api/streak";
import { ClientMessage, type PresenceState } from "@billet/contracts-realtime/client-message";
import { ServerMessage } from "@billet/contracts-realtime/server-message";
import {
  type DemoBotAction,
  DemoBotState,
  demoBotStep,
  nextWakeAt,
  guessSeen,
  noteSeen,
  startDemoBot,
} from "@billet/backend-demo-partner/demo-bot";
import { isMember } from "@billet/backend-pair-room/decide";
import type { RoomJoin } from "@billet/backend-pair-room/room-command";
import type { RoomDecision } from "@billet/backend-pair-room/room-decision";
import { type PurchaseCredit, RoomService } from "@billet/backend-pair-room/room-service";
import type { RoomState, SequencedNote } from "@billet/backend-pair-room/room-state";
import { shopOf } from "@billet/backend-pair-room/shop-view";
import { GiftsRoom, type GiftCommand, type GiftsResult } from "@billet/backend-pair-room/gifts";
import type { ListsResult } from "@billet/backend-pair-room/lists";
import {
  pickKeyOf,
  PickTonightRoom,
  type PickTonightCommand,
  type PickTonightResult,
} from "@billet/backend-pair-room/pick-tonight";
import { GuessRoom, type GuessCommand, type GuessResult } from "@billet/backend-pair-room/guess";
import {
  RiddleRoom,
  type RiddleCommand,
  type RiddleResult,
} from "@billet/backend-pair-room/riddle";
import { type RiddleRow, riddleView } from "@billet/backend-pair-room/riddle-rules";
import { RiddleId } from "@billet/contracts-domain/riddle";
import type { ChangeListRequest } from "@billet/contracts-http-api/lists";
import { PairRoomLive } from "./pair-room-runtime.ts";
import { RoomDb } from "./pair-room-sqlite-store.ts";
import { deliveriesOf } from "./pair-room-deliveries.ts";
import { Observability, traced } from "./observability.ts";
import { opaqueRef } from "@billet/backend-observability/opaque-ref";
import {
  deliveryHealth,
  enqueue,
  isDue,
  nextAlarmAt,
  settle,
  type DeliveryEntry,
  type DeliveryOutcome,
  type LaneHealth,
} from "@billet/backend-pair-room/delivery-ledger";
import { openRoomDatabase } from "./room-database.ts";
import * as roomSchema from "./room-schema.ts";
import type { Note } from "@billet/contracts-domain/note";
import { ProviderTokens, sendApns } from "./apns-client.ts";
import {
  enabledPushLanes,
  guessDeliveryId,
  matchDeliveryId,
  reactionDeliveryId,
  riddleDeliveryId,
  riddleEndDeliveryId,
  sendPushLane,
  type PushLaneSettings,
} from "./apns-lanes.ts";
import { dropToken, tokensOf } from "./partner-push-tokens.ts";
import { clockOf } from "./effect-clock.ts";
import { admitFrame, type FrameWindow } from "./frame-window.ts";
import { systemNow } from "./wall-clock.ts";

/** Who is connecting. Only the Worker can reach this object, after it has authenticated them. */
export const ROOM_USER_HEADER = "x-billet-user";

const decodeUser = Schema.decodeUnknownOption(UserId);
const decodeDay = Schema.decodeUnknownOption(LocalDay);
const decodeRiddleId = Schema.decodeUnknownOption(RiddleId);
const decodeDemoBot = Schema.decodeUnknownOption(DemoBotState);

/** Where a demo pair's room keeps its bot's plans; absent in every other room. */
const demoBotKey = "demoBot";
const decodeClientMessage = Schema.decodeUnknownOption(Schema.fromJsonString(ClientMessage));
const encodeServerMessage = Schema.encodeSync(Schema.fromJsonString(ServerMessage));

/** A frame is a stroke or a few numbers; this bounds what a hostile member can make us parse. */
const maxFrameLength = 64 * 1024;
/** Notes sent per storage read while catching a socket up. */
const pageLimit = 100;
/** Open live strokes kept per socket; a begin past it is dropped. Bounds the attachment. */
const maxOpenStrokes = 16;

interface PairRoomEnv extends PushLaneSettings {
  readonly DB: D1Database;
}

/** Kept on each hibernatable socket, so it survives the object leaving memory. */
interface SocketAttachment {
  readonly user: string;
  /** The highest note `seq` this socket has been sent; null before it asked to resume. */
  readonly sentSeq: number | null;
  /** Live strokes this socket began and has not ended, dropped for the partner if it leaves. */
  readonly openStrokes?: ReadonlyArray<number>;
  /** Highest cat journal `seq` sent; null or absent until it resumes with `lastCatSeq`. */
  readonly sentCatSeq?: number | null;
  /** Whether this socket resumed with `activity: true` and is told its user's unread count. */
  readonly activity?: boolean;
  /** Highest reaction `rev` sent; null or absent until it resumes with `lastReactionRev`. */
  readonly sentReactionRev?: number | null;
  /** Whether this socket resumed with `shop: true` and is sent the pair's shop when it changes. */
  readonly shop?: boolean;
  /** Resumed with `lists: true`: sent the pair's lists when they change. */
  readonly lists?: boolean;
  /** Whether this socket resumed with `moods: true` and is told each check-in. */
  readonly moods?: boolean;
  /** Whether this socket resumed with `guess: true` and is told how Who knows who goes. */
  readonly guess?: boolean;
  /** Whether this socket resumed with `riddle: true` and is sent each draw-guess change. */
  readonly riddle?: boolean;
  /** Whether this socket resumed with `streak: true` and is sent the pair's streak when it changes. */
  readonly streak?: boolean;
}

const shopOutputs: ReadonlySet<string> = new Set([
  "CoinsEntered",
  "InksGranted",
  "ItemsGranted",
  "WishlistChanged",
  "LayoutChanged",
  "GiftOpened",
  "BonusPaid",
]);

const attachmentOf = (socket: WebSocket): SocketAttachment | undefined =>
  (socket.deserializeAttachment() as SocketAttachment | null) ?? undefined;

const send = (socket: WebSocket, message: ServerMessage): void => {
  if (socket.readyState === WebSocket.OPEN) socket.send(encodeServerMessage(message));
};

/**
 * The runtime holds this room's command lock, so it stays per object: never share a `memoMap`.
 */
export class PairRoom extends DurableObject {
  /**
   * A failed migration resets the object, so each request retries; the scope is never closed.
   */
  private readonly database = this.ctx.blockConcurrencyWhile(() =>
    Effect.runPromise(openRoomDatabase(this.ctx.storage).pipe(Scope.provide(Scope.makeUnsafe()))),
  );

  /** Set by `destroy`: the tables are gone, so closing sockets has nothing to settle. */
  private destroyed = false;

  private readonly frameWindows = new WeakMap<WebSocket, FrameWindow>();

  private readonly runtime = this.database.then((database) =>
    ManagedRuntime.make(
      Layer.mergeAll(
        PairRoomLive.pipe(Layer.provide(Layer.succeed(RoomDb, database))),
        Observability,
        Layer.succeed(
          Clock.Clock,
          clockOf(() => this.clock()),
        ),
      ),
    ),
  );

  /** The room's clock, for its notes' times and its delivery alarms; tests replace it. */
  protected clock(): number {
    return systemNow();
  }

  private get roomEnv(): PairRoomEnv {
    return this.env as PairRoomEnv;
  }

  /** APNs widget and alert lanes need an APNs key; Live Activity needs `LIVE_ACTIVITY_PUSH=on`. */
  protected deliveryLanes: ReadonlyArray<string> = enabledPushLanes(this.roomEnv);

  /** Undefined without an APNs key: the alarm has nothing to send. */
  protected laneSender:
    | {
        readonly send: (
          entry: Pick<DeliveryEntry, "noteId" | "lane" | "attempts">,
        ) => Promise<DeliveryOutcome>;
      }
    | undefined = this.apnsLaneSender();

  private apnsLaneSender() {
    const env = this.roomEnv;
    const key = env.APNS_KEY;
    const keyId = env.APNS_KEY_ID;
    if (!key || !keyId) return undefined;
    const credentials = { key, keyId };
    const nowSeconds = () => Math.floor(this.clock() / 1000);
    const providerTokens = new ProviderTokens(nowSeconds);
    return {
      send: (entry: Pick<DeliveryEntry, "noteId" | "lane" | "attempts">) =>
        sendPushLane(entry, {
          note: (noteId) => this.recentNote(noteId),
          reaction: async (rev) => {
            const [latest] = await this.reactions(rev - 1, 1);
            if (latest?.rev !== rev) return undefined;
            const stored = await this.run((room) => room.noteById(latest.note));
            return stored._tag === "Some"
              ? { reaction: latest, note: stored.value.note }
              : undefined;
          },
          match: async (key, at) => {
            const notice = await (
              await this.runtime
            ).runPromise(PickTonightRoom.use((pick) => pick.notice(key, at)));
            return notice === undefined
              ? undefined
              : { recipient: notice.recipient, name: notice.match.name };
          },
          guess: async (day, member) => {
            const round = decodeDay(day);
            const user = decodeUser(member);
            if (round._tag === "None" || user._tag === "None") return undefined;
            return (await this.runtime).runPromise(
              GuessRoom.use((guess) => guess.notice(round.value, user.value)),
            );
          },
          riddle: async (id) => {
            const riddle = decodeRiddleId(id);
            if (riddle._tag === "None") return undefined;
            const row = await (
              await this.runtime
            ).runPromise(RiddleRoom.use((room) => room.byId(riddle.value)));
            const room = await this.snapshot();
            if (row._tag === "None" || room._tag !== "Active") return undefined;
            const { drawer, word, tries, state } = row.value;
            const guesser = room.members.find((member) => member.user !== drawer)?.user;
            return guesser === undefined
              ? undefined
              : { drawer, guesser, word, tries, state: state._tag };
          },
          recipient: async (note) => {
            const room = await this.snapshot();
            if (room._tag !== "Active") return undefined;
            return room.members.find((member) => member.user !== note.author)?.user;
          },
          tokens: (user, kind) => tokensOf(env.DB, user, kind),
          dropToken: (token, kind) => dropToken(env.DB, token, kind),
          send: (push) => sendApns(push, credentials, providerTokens),
          nowSeconds,
        }),
    };
  }

  /** A note among the room's latest; deliveries are only ever for notes just sent. */
  private async recentNote(noteId: string): Promise<Note | undefined> {
    const room = await this.snapshot();
    const lastSeq = room._tag === "Active" ? room.lastSeq : 0;
    const window = 100;
    const page = await this.notes(Math.max(0, lastSeq - window), window);
    return page.find((entry) => entry.note.id === noteId)?.note;
  }

  /** Names this room in spans without naming the pair: the ref of the id it was opened by. */
  private readonly spanAttributes = {
    "pair.ref": opaqueRef(this.ctx.id.name ?? this.ctx.id.toString()),
  };

  /**
   * A named command is a logged root span; per-frame reads pass no name, so drawing does not log.
   */
  private async run<A>(
    program: (room: RoomService["Service"]) => Effect.Effect<A>,
    name?: string,
  ): Promise<A> {
    const effect = RoomService.use(program);
    return (await this.runtime).runPromise(
      name === undefined
        ? effect
        : effect.pipe(Effect.withSpan(name, { root: true, attributes: this.spanAttributes })),
    );
  }

  async gifts(by: UserId, command: GiftCommand): Promise<GiftsResult> {
    return (await this.runtime).runPromise(
      GiftsRoom.use((gifts) => gifts.run(by, command)).pipe(
        Effect.withSpan(`PairRoom.gifts.${command._tag}`, {
          root: true,
          attributes: this.spanAttributes,
        }),
      ),
    );
  }

  /**
   * A match goes to every lists follower, the swiper included, and is pushed to the first swiper.
   */
  async pickTonight(by: UserId, command: PickTonightCommand): Promise<PickTonightResult> {
    const result = await (
      await this.runtime
    ).runPromise(
      PickTonightRoom.use((pick) => pick.run(by, command)).pipe(
        Effect.withSpan(`PairRoom.pickTonight.${command._tag}`, {
          root: true,
          attributes: this.spanAttributes,
        }),
      ),
    );
    if (result._tag !== "Done") return result;
    const match = result.view.match;
    if (match !== undefined) {
      for (const socket of this.ctx.getWebSockets()) {
        if (attachmentOf(socket)?.lists === true) send(socket, { _tag: "MatchFound", match });
      }
    }
    // A repeated ♥ hands its match over again, in case the first try stored the swipe and failed
    // before saving the delivery. A delivery already saved is left as it is.
    const key = command._tag === "Swipe" ? pickKeyOf(command.title) : undefined;
    const delivered =
      match ??
      (command._tag === "Swipe" && command.choice === "want"
        ? result.view.matches.find((made) => pickKeyOf(made.title) === key)
        : undefined);
    if (delivered !== undefined) {
      await this.enqueueDeliveries(matchDeliveryId(pickKeyOf(delivered.title), delivered.at));
    }
    return result;
  }

  /**
   * Progress goes to the partner's followers; the last answer sends each follower its own reveal.
   */
  async guess(by: UserId, command: GuessCommand): Promise<GuessResult> {
    const { result, progress, revealed, coins } = await (
      await this.runtime
    ).runPromise(
      GuessRoom.use((guess) => guess.run(by, command)).pipe(
        Effect.withSpan(`PairRoom.guess.${command._tag}`, {
          root: true,
          attributes: this.spanAttributes,
        }),
      ),
    );
    if (progress === undefined) return result;
    const { round, member, answered, of, stored } = progress;
    if (stored) {
      for (const socket of this.ctx.getWebSockets()) {
        const attachment = attachmentOf(socket);
        if (attachment?.guess === true && attachment.user !== member) {
          send(socket, { _tag: "GuessProgress", round, answered });
        }
      }
    }
    // A repeated last answer hands its push over again, in case the first try stored the answer
    // and failed before saving the delivery. A delivery already saved is left as it is.
    if (answered === of && !revealed) await this.enqueueDeliveries(guessDeliveryId(round, member));
    // A repeated last answer on a revealed round sends the reveal again, in case the first try
    // stored the answer and failed before it was sent.
    if (revealed) await this.pushReveal();
    if (stored) await this.showDemoBotGuess(member);
    const paid = coins.find(
      (decision) =>
        decision._tag === "Accepted" && decision.outputs.some((o) => shopOutputs.has(o._tag)),
    );
    if (paid !== undefined) await this.pushShop(paid);
    return result;
  }

  /** Each follower gets the change as its own user sees it. */
  async riddle(by: UserId, command: RiddleCommand): Promise<RiddleResult> {
    const { result, changed, push, decision } = await (
      await this.runtime
    ).runPromise(
      RiddleRoom.use((riddles) => riddles.run(by, command)).pipe(
        Effect.withSpan(`PairRoom.riddle.${command._tag}`, {
          root: true,
          attributes: this.spanAttributes,
        }),
      ),
    );
    if (changed !== undefined) this.pushRiddle(changed);
    // A retried send or solving try hands its push over again, as a retried note does.
    if (push !== undefined) {
      const { id } = push.riddle;
      await this.enqueueDeliveries(
        push.kind === "sent" ? riddleDeliveryId(id) : riddleEndDeliveryId(id),
      );
    }
    if (decision?._tag === "Accepted") {
      if (decision.outputs.some((output) => output._tag === "CatEntryAppended")) {
        await this.pushCatEntries();
        await this.pushUnread((member) => member !== by);
      }
      await this.pushShop(decision);
    }
    return result;
  }

  private pushRiddle(row: RiddleRow): void {
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = attachmentOf(socket);
      if (attachment?.riddle === true) {
        send(socket, { _tag: "RiddleChanged", riddle: riddleView(row, attachment.user as UserId) });
      }
    }
  }

  /** A resuming follower gets today's reveal, or else the partner's answered count. */
  private async catchUpGuess(socket: WebSocket, user: UserId): Promise<void> {
    const { result } = await (
      await this.runtime
    ).runPromise(GuessRoom.use((guess) => guess.run(user, { _tag: "View" })));
    if (result._tag !== "Done") return;
    const { round, reveal, score, partnerAnswered } = result.view;
    if (reveal !== undefined) {
      send(socket, { _tag: "GuessRevealed", round: round.id, reveal, score });
    } else if (partnerAnswered > 0) {
      send(socket, { _tag: "GuessProgress", round: round.id, answered: partnerAnswered });
    }
  }

  /** A resuming follower gets each open riddle as it stands. */
  private async catchUpRiddles(socket: WebSocket, user: UserId): Promise<void> {
    const { result } = await (
      await this.runtime
    ).runPromise(RiddleRoom.use((riddles) => riddles.run(user, { _tag: "View" })));
    if (result._tag !== "Listed") return;
    for (const riddle of result.view.open) send(socket, { _tag: "RiddleChanged", riddle });
  }

  private async pushReveal(): Promise<void> {
    const views = new Map<string, GuessResult>();
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = attachmentOf(socket);
      if (attachment?.guess !== true) continue;
      const user = attachment.user as UserId;
      const view =
        views.get(user) ??
        (
          await (
            await this.runtime
          ).runPromise(GuessRoom.use((guess) => guess.run(user, { _tag: "View" })))
        ).result;
      views.set(user, view);
      if (view._tag === "Done" && view.view.reveal !== undefined) {
        send(socket, {
          _tag: "GuessRevealed",
          round: view.view.round.id,
          reveal: view.view.reveal,
          score: view.view.score,
        });
      }
    }
  }

  /**
   * Pushes changes to lists followers, coins to shop followers, an add to the partner's Inbox.
   */
  async lists(by: UserId, request?: ChangeListRequest): Promise<ListsResult> {
    const { result, decision } = await this.run(
      (room) => room.listsFor(by, request),
      request === undefined ? "PairRoom.lists" : `PairRoom.lists.${request.change._tag}`,
    );
    if (decision?._tag !== "Accepted" || result._tag !== "Done") return result;
    const tags = new Set(decision.outputs.map((output) => output._tag));
    if (tags.has("ListSaved") || tags.has("ListDeleted")) {
      for (const socket of this.ctx.getWebSockets()) {
        if (attachmentOf(socket)?.lists === true) {
          send(socket, { _tag: "ListsChanged", lists: result.lists });
        }
      }
    }
    await this.pushShop(decision);
    if (tags.has("ListItemAdded")) await this.pushUnread((member) => member !== by);
    return result;
  }

  open(
    pairId: PairId,
    members: readonly [UserId, UserId],
    joined?: RoomJoin,
  ): Promise<RoomDecision> {
    const command = joined === undefined ? { pairId, members } : { pairId, members, joined };
    return this.run((room) => room.dispatch({ _tag: "Open", ...command }), "PairRoom.open");
  }

  async sendNote(author: UserId, request: SendNoteRequest): Promise<RoomDecision> {
    const decision = await this.run((room) => room.sendNote(author, request), "PairRoom.sendNote");
    if (decision._tag === "Accepted") {
      for (const output of decision.outputs) {
        // A retried send enqueues too: if the first one stored the note and failed before its
        // deliveries were saved, the retry is the only chance to push it. Enqueueing is idempotent.
        if (output._tag === "NoteAppended" || output._tag === "NoteRepeated") {
          await this.enqueueDeliveries(output.entry.note.id);
        }
        if (output._tag === "NoteAppended") await this.showDemoBot(output.entry.note);
      }
      await this.pushNotes();
      await this.pushShop(decision);
      // A note to an adopted cat is also a journal entry.
      if (decision.outputs.some((output) => output._tag === "CatEntryAppended")) {
        await this.pushCatEntries();
      }
      await this.pushUnread((member) => member !== author);
    }
    return decision;
  }

  /** Tells reaction followers; a new reaction also alerts the photo's author. */
  async react(by: UserId, request: ReactRequest): Promise<RoomDecision> {
    const decision = await this.run((room) => room.react(by, request), "PairRoom.react");
    if (decision._tag === "Accepted") {
      for (const output of decision.outputs) {
        if (output._tag === "ReactionSet" && output.reaction.reaction !== undefined) {
          await this.enqueueDeliveries(reactionDeliveryId(output.reaction.rev));
        }
      }
      await this.pushReactions();
      await this.pushUnread((member) => member !== by);
    }
    return decision;
  }

  reactions(afterRev: number, limit: number): Promise<ReadonlyArray<NoteReaction>> {
    return this.run((room) => room.reactionsAfter(afterRev, limit), "PairRoom.reactions");
  }

  /** Moods followers include the caller's own other devices; also moves the partner's Inbox. */
  async setMood(by: UserId, request: SetMoodRequest): Promise<RoomDecision> {
    const decision = await this.run((room) => room.setMood(by, request), "PairRoom.setMood");
    if (decision._tag === "Accepted") {
      for (const output of decision.outputs) {
        if (output._tag === "MoodSet") {
          for (const socket of this.ctx.getWebSockets()) {
            if (attachmentOf(socket)?.moods === true) {
              send(socket, { _tag: "MoodChanged", checkIn: output.checkIn });
            }
          }
        }
      }
      await this.pushUnread((member) => member !== by);
    }
    return decision;
  }

  /** Each member's latest check-in; none while the room is not open. */
  moods(): Promise<ReadonlyArray<MoodCheckIn>> {
    return this.run((room) => room.moods, "PairRoom.moods");
  }

  /**
   * Counts `by`'s day in the streak and tells every socket that follows it; a milestone moves the
   * partner's Inbox count.
   */
  async recordStreakDay(by: UserId, request: RecordStreakDayRequest): Promise<RoomDecision> {
    const decision = await this.run(
      (room) => room.recordStreakDay(by, request),
      "PairRoom.recordStreakDay",
    );
    this.pushStreak(decision);
    if (
      decision._tag === "Accepted" &&
      decision.outputs.some(
        (output) => output._tag === "StreakChanged" && output.reached !== undefined,
      )
    ) {
      await this.pushUnread((member) => member !== by);
    }
    return decision;
  }

  /** Restores the streak for the pair and tells every socket that follows it. */
  async restoreStreak(by: UserId, request: RestoreStreakRequest): Promise<RoomDecision> {
    const decision = await this.run(
      (room) => room.restoreStreak(by, request),
      "PairRoom.restoreStreak",
    );
    this.pushStreak(decision);
    return decision;
  }

  private pushStreak(decision: RoomDecision): void {
    if (decision._tag !== "Accepted") return;
    for (const output of decision.outputs) {
      if (output._tag === "StreakChanged") {
        for (const socket of this.ctx.getWebSockets()) {
          if (attachmentOf(socket)?.streak === true) {
            send(socket, { _tag: "StreakChanged", streak: output.streak });
          }
        }
      }
    }
  }

  /** The pair's streak; null while the room is not open. */
  streak(): Promise<LoveStreak | null> {
    return this.run((room) => room.streak, "PairRoom.streak");
  }

  async saveCat(
    user: UserId,
    request: SaveCatRequest,
    natureSeed: NatureSeed,
  ): Promise<RoomDecision> {
    const decision = await this.run(
      (room) => room.saveCat(user, request, natureSeed),
      "PairRoom.saveCat",
    );
    if (decision._tag === "Accepted") {
      for (const output of decision.outputs) {
        if (output._tag === "CatSaved") {
          // Only sockets that follow the journal: an older build never sees a cat frame.
          for (const socket of this.ctx.getWebSockets()) {
            if (attachmentOf(socket)?.sentCatSeq != null) {
              send(socket, { _tag: "CatSaved", cat: output.cat });
            }
          }
        }
      }
      await this.pushUnread((member) => member !== user);
    }
    return decision;
  }

  async recordCatEvent(by: UserId, request: RecordCatEventRequest): Promise<RoomDecision> {
    const decision = await this.run(
      (room) => room.recordCatEvent(by, request),
      "PairRoom.recordCatEvent",
    );
    if (decision._tag === "Accepted") {
      await this.pushCatEntries();
      await this.pushShop(decision);
      await this.pushUnread((member) => member !== by);
    }
    return decision;
  }

  /** One page of the Inbox, newest first, as `caller` sees it. */
  activity(
    caller: UserId,
    before: ActivityCursor | undefined,
    limit: number,
  ): Promise<ActivityResponse> {
    return this.run((room) => room.activityPage(caller, before, limit), "PairRoom.activity");
  }

  /** Moves `user`'s read mark forward and tells their other devices the new count. */
  async markActivityRead(user: UserId, upTo: ActivityCursor): Promise<number> {
    const unread = await this.run(
      (room) => room.markActivityRead(user, upTo),
      "PairRoom.markActivityRead",
    );
    this.sendUnread((member) => member === user, new Map([[user, unread]]));
    return unread;
  }

  private async pushShop(decision: RoomDecision): Promise<void> {
    if (decision._tag !== "Accepted") return;
    if (!decision.outputs.some((output) => shopOutputs.has(output._tag))) return;
    const sockets = this.ctx
      .getWebSockets()
      .filter((socket) => attachmentOf(socket)?.shop === true);
    if (sockets.length === 0) return;
    const shop = await this.shop();
    if (shop === null) return;
    for (const socket of sockets) send(socket, { _tag: "ShopChanged", shop });
  }

  /** Each count is read once, however many devices a user has. */
  private async pushUnread(who: (user: string) => boolean): Promise<void> {
    const users = new Set<string>();
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = attachmentOf(socket);
      if (attachment?.activity === true && who(attachment.user)) users.add(attachment.user);
    }
    if (users.size === 0) return;
    const counts = new Map<string, number>();
    for (const user of users) {
      counts.set(user, await this.run((room) => room.unread(user as UserId)));
    }
    this.sendUnread(who, counts);
  }

  private sendUnread(who: (user: string) => boolean, counts: ReadonlyMap<string, number>): void {
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = attachmentOf(socket);
      const unread = attachment === undefined ? undefined : counts.get(attachment.user);
      if (attachment?.activity === true && who(attachment.user) && unread !== undefined) {
        send(socket, { _tag: "ActivityUnread", unread });
      }
    }
  }

  /** The cat now, by the room's clock, or null while the room is not open. */
  cat(): Promise<CatResponse | null> {
    return this.run((room) => room.catView, "PairRoom.cat");
  }

  catJournal(afterSeq: number, limit: number): Promise<ReadonlyArray<CatEntry>> {
    return this.run((room) => room.catEntriesAfter(afterSeq, limit), "PairRoom.catJournal");
  }

  /** Once per lane per note: enqueueing is idempotent. */
  private async enqueueDeliveries(noteId: string): Promise<void> {
    if (this.deliveryLanes.length === 0) return;
    const deliveries = deliveriesOf(await this.database);
    const now = this.clock();
    for (const lane of this.deliveryLanes) {
      const existing = await Effect.runPromise(deliveries.find(noteId, lane));
      if (existing === undefined) {
        await Effect.runPromise(deliveries.save(enqueue(existing, noteId, lane, now)));
      }
    }
    await this.scheduleAlarm();
  }

  /** One alarm for deliveries and the demo bot; without a lane sender deliveries set none. */
  private async scheduleAlarm(): Promise<void> {
    const entries = await Effect.runPromise(deliveriesOf(await this.database).all);
    const bot = await this.demoBot();
    const times = [
      this.laneSender === undefined ? undefined : nextAlarmAt(entries),
      bot === undefined ? undefined : nextWakeAt(bot),
    ].filter((at) => at !== undefined);
    if (times.length > 0) await this.ctx.storage.setAlarm(Math.min(...times));
    else await this.ctx.storage.deleteAlarm();
  }

  async deliveryHealth(): Promise<Readonly<Record<string, LaneHealth>>> {
    return deliveryHealth(await this.deliveries());
  }

  async deliveries(): Promise<ReadonlyArray<DeliveryEntry>> {
    return Effect.runPromise(deliveriesOf(await this.database).all);
  }

  /**
   * A throwing sender is a retry; delivered and abandoned entries never resend, so reruns are safe.
   */
  override async alarm(): Promise<void> {
    const sender = this.laneSender;
    if (sender !== undefined) await this.deliver(sender);
    await this.actAsDemoBot();
    await this.scheduleAlarm();
  }

  private deliver(sender: NonNullable<PairRoom["laneSender"]>): Promise<void> {
    return traced("PairRoom.alarm", this.spanAttributes, async (context) => {
      const deliveries = deliveriesOf(await this.database);
      const now = this.clock();
      for (const entry of await Effect.runPromise(deliveries.all)) {
        if (!isDue(entry, now)) continue;
        const outcome = await sender.send(entry).catch((): DeliveryOutcome => "Retry");
        const settled = settle(entry, outcome, this.clock());
        await Effect.runPromise(deliveries.save(settled));
        // One line per try: summing these per lane gives the delivery success rate.
        await Effect.runPromiseWith(context)(
          Effect.logInfo("delivery").pipe(
            Effect.annotateLogs({
              event: "delivery",
              lane: entry.lane,
              outcome,
              status: settled.status,
              attempts: settled.attempts,
            }),
          ),
        );
      }
    });
  }

  /** Acts through the calls a phone reaches. Repeating it for the same bot keeps its plans. */
  async startDemo(owner: UserId, bot: UserId): Promise<void> {
    if ((await this.demoBot())?.bot !== bot) {
      await this.ctx.storage.put(demoBotKey, startDemoBot(bot, owner, this.clock()));
    }
    await this.scheduleAlarm();
  }

  async stopDemo(): Promise<void> {
    await this.ctx.storage.delete(demoBotKey);
    await this.scheduleAlarm();
  }

  private async demoBot(): Promise<DemoBotState | undefined> {
    const stored = decodeDemoBot(await this.ctx.storage.get(demoBotKey));
    return stored._tag === "Some" ? stored.value : undefined;
  }

  /** Storage reads and writes only. */
  private async showDemoBot(note: Note): Promise<void> {
    const bot = await this.demoBot();
    if (bot === undefined) return;
    const next = noteSeen(bot, note, this.clock());
    if (next === bot) return;
    await this.ctx.storage.put(demoBotKey, next);
    await this.scheduleAlarm();
  }

  private async showDemoBotGuess(by: UserId): Promise<void> {
    const bot = await this.demoBot();
    if (bot === undefined) return;
    const next = guessSeen(bot, by, this.clock());
    if (next === bot) return;
    await this.ctx.storage.put(demoBotKey, next);
    await this.scheduleAlarm();
  }

  /**
   * Plans move on before acting, so a failed action is dropped; a non-member bot is stopped.
   */
  private async actAsDemoBot(): Promise<void> {
    const bot = await this.demoBot();
    if (bot === undefined) return;
    const { action, state } = demoBotStep(bot, this.clock());
    if (state !== bot) await this.ctx.storage.put(demoBotKey, state);
    if (action === undefined) return;
    const room = await this.snapshot();
    if (room._tag === "Active" && !isMember(room, bot.bot)) {
      await this.ctx.storage.delete(demoBotKey);
      return;
    }
    await this.demoBotDoes(bot.bot, action).catch((error: unknown) =>
      this.run(() => Effect.logWarning("demo bot action failed", error)),
    );
  }

  private async demoBotDoes(bot: UserId, action: DemoBotAction): Promise<void> {
    switch (action._tag) {
      case "SendNote":
        await this.sendNote(bot, action.request);
        return;
      case "React":
        await this.react(bot, action.request);
        return;
      case "RecordCatEvent":
        await this.recordCatEvent(bot, action.request);
        return;
      case "OpenGift":
        await this.openGift(bot, undefined);
        return;
      case "PlayGuess": {
        const view = await this.guess(bot, { _tag: "View" });
        if (view._tag !== "Done") return;
        const { round, answers } = view.view;
        const open = round.questions.filter((q) => !answers.some((a) => a.question === q));
        for (const [i, question] of open.entries()) {
          const option = action.options[i % action.options.length] ?? 0;
          await this.guess(bot, { _tag: "Answer", round: round.id, question, option });
        }
        return;
      }
    }
  }

  setPresence(user: UserId, state: PresenceState): Promise<RoomDecision> {
    return this.run(
      (room) => room.dispatch({ _tag: "SetPresence", user, state }),
      "PairRoom.setPresence",
    );
  }

  snapshot(): Promise<RoomState> {
    return this.run((room) => room.state);
  }

  /** In the order bought. The free ink is not listed. */
  inks(): Promise<ReadonlyArray<InkId>> {
    return this.run((room) =>
      room.state.pipe(Effect.map((state) => (state._tag === "Active" ? state.inks : []))),
    );
  }

  /** Purchases kept from an earlier pair. */
  async grantItems(items: ReadonlyArray<RoomItemId>): Promise<RoomDecision> {
    const decision = await this.run(
      (room) => room.dispatch({ _tag: "GrantItems", items }),
      "PairRoom.grantItems",
    );
    await this.pushShop(decision);
    return decision;
  }

  /** The wallet calls it once it has taken the coins. */
  async grantInks(inks: ReadonlyArray<InkId>): Promise<RoomDecision> {
    const decision = await this.run(
      (room) => room.dispatch({ _tag: "GrantInks", inks }),
      "PairRoom.grantInks",
    );
    await this.pushShop(decision);
    return decision;
  }

  /** Null while the room is not open. A room owed its welcome coins gets them first. */
  coins(after: CoinEntryId | undefined, limit: number): Promise<CoinsResponse | null> {
    return this.run(
      (room) =>
        Effect.all([room.settled, room.coinEntriesAfter(after, limit)]).pipe(
          Effect.map(([state, entries]) =>
            state._tag === "Active" ? { balance: state.wallet.balance, entries } : null,
          ),
        ),
      "PairRoom.coins",
    );
  }

  /** A repeated `id` answers with the first buy. */
  async buy(by: UserId, id: IdempotencyKey, ink: InkId, terms?: PriceTerms): Promise<RoomDecision> {
    const decision = await this.run((room) => room.buy(by, id, ink, terms), "PairRoom.buy");
    await this.pushShop(decision);
    return decision;
  }

  /** Null while the room is not open. A room owed its welcome coins gets them first. */
  shop(): Promise<ShopResponse | null> {
    return this.run(
      (room) =>
        room.settled.pipe(Effect.map((state) => (state._tag === "Active" ? shopOf(state) : null))),
      "PairRoom.shop",
    );
  }

  /** A repeated `id` answers with the first order. */
  async order(
    by: UserId,
    id: IdempotencyKey,
    offer: ShopOffer,
    utcOffsetSeconds?: number,
    terms?: PriceTerms,
  ): Promise<RoomDecision> {
    const decision = await this.run(
      (room) => room.order(by, id, offer, utcOffsetSeconds, terms),
      "PairRoom.order",
    );
    return this.afterCoins(decision, by);
  }

  /** Once a day for the pair. */
  async openGift(by: UserId, utcOffsetSeconds: number | undefined): Promise<RoomDecision> {
    const decision = await this.run(
      (room) => room.openGift(by, utcOffsetSeconds),
      "PairRoom.openGift",
    );
    return this.afterCoins(decision, by);
  }

  /** Once per collection. */
  async claimBonus(by: UserId, collection: CollectionId): Promise<RoomDecision> {
    const decision = await this.run(
      (room) => room.claimBonus(by, collection),
      "PairRoom.claimBonus",
    );
    return this.afterCoins(decision, by);
  }

  /** Once per ref. An earn is no Inbox item. */
  async earn(
    by: UserId,
    event: EarnEvent,
    utcOffsetSeconds: number | undefined,
  ): Promise<RoomDecision> {
    const decision = await this.run(
      (room) => room.earn(by, event, utcOffsetSeconds),
      "PairRoom.earn",
    );
    await this.pushShop(decision);
    return decision;
  }

  /** Coins bought with money, once per entry id. No Inbox item. */
  creditPurchase(credit: PurchaseCredit): Promise<RoomDecision> {
    return this.run((room) => room.creditPurchase(credit), "PairRoom.creditPurchase");
  }

  /** A treat's meal goes to the journal's followers; an order, gift or bonus is an Inbox item. */
  private async afterCoins(decision: RoomDecision, by: UserId): Promise<RoomDecision> {
    if (decision._tag === "Accepted" && decision.outputs.some((o) => o._tag !== "CoinsRepeated")) {
      if (decision.outputs.some((output) => output._tag === "CatEntryAppended")) {
        await this.pushCatEntries();
      }
      await this.pushUnread((member) => member !== by);
    }
    await this.pushShop(decision);
    return decision;
  }

  async setWish(
    by: UserId,
    item: RoomItemId,
    wished: boolean,
    offered?: boolean,
  ): Promise<RoomDecision> {
    const decision = await this.run(
      (room) => room.setWish(by, item, wished, offered),
      "PairRoom.setWish",
    );
    await this.pushShop(decision);
    return decision;
  }

  async changeLayout(by: UserId, id: IdempotencyKey, change: LayoutChange): Promise<RoomDecision> {
    const decision = await this.run(
      (room) => room.changeLayout(by, id, change),
      "PairRoom.changeLayout",
    );
    await this.pushShop(decision);
    return decision;
  }

  notes(afterSeq: number, limit: number): Promise<ReadonlyArray<SequencedNote>> {
    return this.run((room) => room.notesAfter(afterSeq, limit), "PairRoom.notes");
  }

  /**
   * Deletes the leaver's notes and deliveries and the cat; returns the notes so images go too.
   */
  async forgetMember(user: UserId): Promise<ReadonlyArray<SequencedNote>> {
    const forgotten = await this.run((room) => room.forgetAuthor(user), "PairRoom.forgetMember");
    await (await this.runtime).runPromise(GiftsRoom.use((gifts) => gifts.forget));
    await (await this.runtime).runPromise(PickTonightRoom.use((pick) => pick.forget));
    await (await this.runtime).runPromise(GuessRoom.use((guess) => guess.forget));
    await (await this.runtime).runPromise(RiddleRoom.use((riddles) => riddles.forget));
    await this.run((room) => room.forgetLists, "PairRoom.forgetLists");
    const deliveries = deliveriesOf(await this.database);
    for (const { note } of forgotten) await Effect.runPromise(deliveries.forget(note.id));
    await this.endSessions();
    return forgotten;
  }

  /**
   * Empties every room table but keeps them, so a late request such as account erasure works.
   */
  async destroy(): Promise<void> {
    this.destroyed = true;
    await this.endSessions();
    await this.ctx.storage.deleteAlarm();
    const tables = Object.values(roomSchema).flatMap((value) =>
      is(value, SQLiteTable) ? [value] : [],
    );
    this.ctx.storage.transactionSync(() => {
      for (const table of tables) this.ctx.storage.sql.exec(`DELETE FROM "${getTableName(table)}"`);
    });
  }

  /** Also stills a demo pair's bot: the pair has ended and the Worker won't route here again. */
  async endSessions(): Promise<void> {
    for (const socket of this.ctx.getWebSockets()) {
      try {
        socket.close(1000, "pair ended");
      } catch {
        // Already closing: nothing left to end.
      }
    }
    if ((await this.demoBot()) !== undefined) await this.stopDemo();
  }

  /** Hibernatable: the object can leave memory while the socket stays open. */
  override async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response(null, { status: 426 });
    }
    const user = decodeUser(request.headers.get(ROOM_USER_HEADER));
    if (user._tag === "None") return new Response(null, { status: 400 });
    if (!isMember(await this.snapshot(), user.value)) return new Response(null, { status: 403 });

    const { 0: client, 1: server } = new WebSocketPair();
    this.ctx.acceptWebSocket(server, [user.value]);
    // `sentSeq` is null until the client sends Resume: no note frame reaches a socket before then.
    const attachment: SocketAttachment = { user: user.value, sentSeq: null };
    server.serializeAttachment(attachment);
    const room = await this.snapshot();
    if (room._tag === "Active") {
      const partner = room.members.find((member) => member.user !== user.value);
      if (partner !== undefined) {
        send(server, {
          _tag: "Presence",
          state: this.hasOpenSocket(partner.user) ? partner.presence : "away",
        });
      }
      const own = room.members.find((member) => member.user === user.value);
      if (own !== undefined && !this.hasOpenSocket(user.value, server)) {
        this.toPartner(user.value, { _tag: "Presence", state: own.presence });
      }
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  /** Drops frames that are not text, too large, or not a `ClientMessage`; too large also closes. */
  override async webSocketMessage(socket: WebSocket, data: string | ArrayBuffer): Promise<void> {
    if (typeof data !== "string") return;
    if (data.length > maxFrameLength) {
      socket.close(1009, "frame too large");
      return;
    }
    if (!this.admitFrame(socket)) return;
    const message = decodeClientMessage(data);
    const attachment = attachmentOf(socket);
    if (message._tag === "None" || attachment === undefined) return;

    switch (message.value._tag) {
      case "Resume": {
        // Start from what the client holds, never more. Each flag it leaves out (`lastCatSeq`,
        // `activity`, `shop`, `lists`, `guess`, `riddle`) is a stream it does not follow.
        const {
          lastSeq,
          lastCatSeq,
          activity,
          lastReactionRev,
          shop,
          lists,
          moods,
          guess,
          riddle,
          streak,
        } = message.value;
        socket.serializeAttachment({
          ...attachment,
          sentSeq: Math.max(0, lastSeq),
          sentCatSeq: lastCatSeq === undefined ? null : Math.max(0, lastCatSeq),
          activity: activity === true,
          sentReactionRev: lastReactionRev === undefined ? null : Math.max(0, lastReactionRev),
          shop: shop === true,
          lists: lists === true,
          moods: moods === true,
          guess: guess === true,
          riddle: riddle === true,
          streak: streak === true,
        } satisfies SocketAttachment);
        await this.catchUp(socket);
        await this.catchUpCat(socket);
        await this.catchUpReactions(socket);
        if (activity === true) {
          const unread = await this.run((room) => room.unread(attachment.user as UserId));
          send(socket, { _tag: "ActivityUnread", unread });
        }
        const current = shop === true ? await this.shop() : null;
        if (current !== null) send(socket, { _tag: "ShopChanged", shop: current });
        const held = lists === true ? await this.lists(attachment.user as UserId) : undefined;
        if (held?._tag === "Done") send(socket, { _tag: "ListsChanged", lists: held.lists });
        // Only the latest check-ins are kept, so a resume is sent those instead of what it missed.
        if (moods === true) {
          for (const checkIn of await this.moods()) send(socket, { _tag: "MoodChanged", checkIn });
        }
        // The game state now, so what the partner did while this socket was away still arrives.
        if (guess === true) await this.catchUpGuess(socket, attachment.user as UserId);
        if (riddle === true) await this.catchUpRiddles(socket, attachment.user as UserId);
        const pairStreak = streak === true ? await this.streak() : null;
        if (pairStreak !== null) send(socket, { _tag: "StreakChanged", streak: pairStreak });
        return;
      }
      case "Stroke": {
        // Live strokes are not stored or replayed: `seq` places one among the notes, as the
        // room's last note when it was relayed.
        const room = await this.snapshot();
        const seq = room._tag === "Active" ? room.lastSeq : 0;
        this.toPartner(attachment.user, { _tag: "Stroke", seq, stroke: message.value.stroke });
        return;
      }
      case "Presence": {
        const decision = await this.setPresence(attachment.user as UserId, message.value.state);
        if (decision._tag === "Accepted") {
          this.toPartner(attachment.user, { _tag: "Presence", state: message.value.state });
        }
        return;
      }
      case "StrokeBegin": {
        const open = attachment.openStrokes ?? [];
        if (!open.includes(message.value.id)) {
          if (open.length >= maxOpenStrokes) return;
          socket.serializeAttachment({
            ...attachment,
            openStrokes: [...open, message.value.id],
          } satisfies SocketAttachment);
        }
        this.toPartner(attachment.user, message.value);
        return;
      }
      case "StrokePoints":
        // Points of a stroke this socket never began would draw nothing on the partner's side.
        if (attachment.openStrokes?.includes(message.value.id) !== true) return;
        // The Workers clock moves on at each incoming event, so this is when the frame arrived.
        this.toPartner(attachment.user, { ...message.value, relayedAt: Date.now() });
        return;
      case "StrokeEnd": {
        const open = attachment.openStrokes ?? [];
        const ended = message.value.id;
        if (!open.includes(ended)) return;
        socket.serializeAttachment({
          ...attachment,
          openStrokes: open.filter((id) => id !== ended),
        } satisfies SocketAttachment);
        this.toPartner(attachment.user, message.value);
        return;
      }
      case "Clear":
        this.toPartner(attachment.user, message.value);
        return;
    }
  }

  /** Counts a frame against its socket's window, in memory: hibernation resets the window. */
  private admitFrame(socket: WebSocket): boolean {
    const { window, admitted } = admitFrame(this.frameWindows.get(socket), this.clock());
    this.frameWindows.set(socket, window);
    return admitted;
  }

  private dropOpenStrokes(socket: WebSocket): void {
    const attachment = attachmentOf(socket);
    if (attachment === undefined) return;
    for (const id of attachment.openStrokes ?? []) {
      this.toPartner(attachment.user, { _tag: "StrokeDropped", id });
    }
    socket.serializeAttachment({ ...attachment, openStrokes: [] } satisfies SocketAttachment);
  }

  /** Oldest first, without repeats. */
  private async catchUp(socket: WebSocket): Promise<void> {
    for (;;) {
      const attachment = attachmentOf(socket);
      if (attachment?.sentSeq == null || socket.readyState !== WebSocket.OPEN) return;
      const page = await this.notes(attachment.sentSeq, pageLimit);
      if (page.length === 0) return;
      for (const entry of page) {
        // Another catch-up may have sent some of this page while this one was waiting.
        const current = attachmentOf(socket)?.sentSeq;
        if (current == null || entry.seq <= current) continue;
        send(socket, { _tag: "NoteReceived", seq: entry.seq, note: entry.note });
        socket.serializeAttachment({
          ...attachmentOf(socket),
          user: attachment.user,
          sentSeq: entry.seq,
        } satisfies SocketAttachment);
      }
    }
  }

  private async catchUpCat(socket: WebSocket): Promise<void> {
    for (;;) {
      const attachment = attachmentOf(socket);
      if (attachment?.sentCatSeq == null || socket.readyState !== WebSocket.OPEN) return;
      const page = await this.catJournal(attachment.sentCatSeq, pageLimit);
      if (page.length === 0) return;
      for (const entry of page) {
        const current = attachmentOf(socket);
        if (current?.sentCatSeq == null || entry.seq <= current.sentCatSeq) continue;
        send(socket, { _tag: "CatEntryAdded", entry });
        socket.serializeAttachment({
          ...current,
          sentCatSeq: entry.seq,
        } satisfies SocketAttachment);
      }
    }
  }

  private async catchUpReactions(socket: WebSocket): Promise<void> {
    for (;;) {
      const attachment = attachmentOf(socket);
      if (attachment?.sentReactionRev == null || socket.readyState !== WebSocket.OPEN) return;
      const page = await this.reactions(attachment.sentReactionRev, pageLimit);
      if (page.length === 0) return;
      for (const reaction of page) {
        const current = attachmentOf(socket);
        if (current?.sentReactionRev == null || reaction.rev <= current.sentReactionRev) continue;
        send(socket, { _tag: "ReactionChanged", reaction });
        socket.serializeAttachment({
          ...current,
          sentReactionRev: reaction.rev,
        } satisfies SocketAttachment);
      }
    }
  }

  private async pushReactions(): Promise<void> {
    await Promise.all(this.ctx.getWebSockets().map((socket) => this.catchUpReactions(socket)));
  }

  private async pushCatEntries(): Promise<void> {
    await Promise.all(this.ctx.getWebSockets().map((socket) => this.catchUpCat(socket)));
  }

  private async pushNotes(): Promise<void> {
    await Promise.all(this.ctx.getWebSockets().map((socket) => this.catchUp(socket)));
  }

  private toPartner(user: string, message: ServerMessage): void {
    for (const socket of this.ctx.getWebSockets()) {
      if (attachmentOf(socket)?.user !== user) send(socket, message);
    }
  }

  /** Whether `user` has an open socket here besides `except`. */
  private hasOpenSocket(user: string, except?: WebSocket): boolean {
    return this.ctx
      .getWebSockets(user)
      .some((socket) => socket !== except && socket.readyState === WebSocket.OPEN);
  }

  /**
   * The user has no open socket left: the partner is told they are away, and a drawing they left
   * is stored as stopped, so their next connect announces them idle.
   */
  private async leave(socket: WebSocket): Promise<void> {
    const user = attachmentOf(socket)?.user;
    if (user === undefined) return;
    if (this.hasOpenSocket(user, socket)) return;
    const room = await this.snapshot();
    if (room._tag !== "Active") return;
    if (room.members.find((member) => member.user === user)?.presence === "drawing") {
      await this.setPresence(user as UserId, "idle");
    }
    this.toPartner(user, { _tag: "Presence", state: "away" });
  }

  /**
   * 1006 and 1015: connection gone, `close` would throw. 1005: no code was sent, none to echo.
   */
  override async webSocketClose(socket: WebSocket, code: number): Promise<void> {
    if (this.destroyed) return;
    // Presence and open strokes are settled before the early return below: a dropped phone takes
    // that return.
    this.dropOpenStrokes(socket);
    await this.leave(socket);
    if (code === 1006 || code === 1015) return;
    try {
      socket.close(code === 1005 ? 1000 : code);
    } catch {
      // A client can send a code the runtime refuses to echo (RFC 6455 forbids them). Answer
      // with a protocol error instead of leaving the connection open.
      socket.close(1002, "invalid close code");
    }
  }
}
