import { DurableObject } from "cloudflare:workers";
import { Clock, Effect, Layer, ManagedRuntime, Schema, Scope } from "effect";
import { UserId } from "@billet/contracts-domain/ids";
import type { InkId } from "@billet/contracts-domain/inks";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { CatEntry, NatureSeed } from "@billet/contracts-domain/cat";
import type {
  CatResponse,
  RecordCatEventRequest,
  SaveCatRequest,
} from "@billet/contracts-http-api/cat";
import type { SendNoteRequest } from "@billet/contracts-http-api/note";
import { ClientMessage, type PresenceState } from "@billet/contracts-realtime/client-message";
import { ServerMessage } from "@billet/contracts-realtime/server-message";
import { isMember } from "@billet/backend-pair-room/decide";
import type { RoomDecision } from "@billet/backend-pair-room/room-decision";
import { RoomService } from "@billet/backend-pair-room/room-service";
import type { RoomState, SequencedNote } from "@billet/backend-pair-room/room-state";
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
import type { Note } from "@billet/contracts-domain/note";
import { ProviderTokens, sendApns } from "./apns-client.ts";
import { enabledPushLanes, sendPushLane, type PushLaneSettings } from "./apns-lanes.ts";
import { dropToken, tokensOf } from "./partner-push-tokens.ts";
import { clockOf } from "./effect-clock.ts";
import { admitFrame, type FrameWindow } from "./frame-window.ts";
import { systemNow } from "./wall-clock.ts";

/** Who is connecting. Only the Worker can reach this object, after it has authenticated them. */
export const ROOM_USER_HEADER = "x-billet-user";

const decodeUser = Schema.decodeUnknownOption(UserId);
const decodeClientMessage = Schema.decodeUnknownOption(Schema.fromJsonString(ClientMessage));
const encodeServerMessage = Schema.encodeSync(Schema.fromJsonString(ServerMessage));

/** A frame is a stroke or a few numbers; this bounds what a hostile member can make us parse. */
const maxFrameLength = 64 * 1024;
/** Notes sent per storage read while catching a socket up. */
const pageLimit = 100;
/** Open live strokes kept per socket; a begin past it is dropped. Bounds the attachment. */
const maxOpenStrokes = 16;

/** The Worker bindings the room reads: the directory for tokens, and the APNs settings. */
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
  /**
   * The highest cat journal `seq` this socket has been sent; null (or absent, on a socket accepted
   * before the cat existed) until it resumes with `lastCatSeq`.
   */
  readonly sentCatSeq?: number | null;
}

const attachmentOf = (socket: WebSocket): SocketAttachment | undefined =>
  (socket.deserializeAttachment() as SocketAttachment | null) ?? undefined;

const send = (socket: WebSocket, message: ServerMessage): void => {
  if (socket.readyState === WebSocket.OPEN) socket.send(encodeServerMessage(message));
};

/**
 * One couple. This class only moves calls into the runtime: the rules are in
 * `@billet/backend-pair-room` and the SQL is in `pair-room-sqlite-store.ts`.
 *
 * The runtime holds the lock that orders this room's commands, so it must stay per object: do not
 * share a `memoMap` here. It holds no resources that outlive the object, and Durable Objects have
 * no shutdown hook, so eviction simply drops it and the next event builds a new one.
 */
export class PairRoom extends DurableObject {
  /**
   * Opens the database and applies pending migrations before any event is delivered. A migration
   * that cannot apply rejects here, which resets the object, so every request retries it. The
   * database lives in a scope that is never closed: the object has no shutdown hook, and eviction
   * drops it.
   */
  private readonly database = this.ctx.blockConcurrencyWhile(() =>
    Effect.runPromise(openRoomDatabase(this.ctx.storage).pipe(Scope.provide(Scope.makeUnsafe()))),
  );

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

  /**
   * The lanes each accepted note is handed to: the APNs widget and alert lanes when the Worker has
   * an APNs key, and the Live Activity lane when `LIVE_ACTIVITY_PUSH` is `on` (off by default).
   */
  protected deliveryLanes: ReadonlyArray<string> = enabledPushLanes(this.roomEnv);

  /** Tries one lane once. Without an APNs key the alarm has nothing to do. */
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
   * Runs one room command. A named command is a root span (`PairRoom.sendNote`) and writes a
   * `trace` line; reads made per frame (`snapshot`) pass no name, so a drawing does not log.
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

  open(pairId: PairId, members: readonly [UserId, UserId]): Promise<RoomDecision> {
    return this.run((room) => room.dispatch({ _tag: "Open", pairId, members }), "PairRoom.open");
  }

  async sendNote(author: UserId, request: SendNoteRequest): Promise<RoomDecision> {
    const decision = await this.run((room) => room.sendNote(author, request), "PairRoom.sendNote");
    if (decision._tag === "Accepted") {
      for (const output of decision.outputs) {
        if (output._tag === "NoteAppended") await this.enqueueDeliveries(output.entry.note.id);
      }
      await this.pushNotes();
      // A note to an adopted cat is also a journal entry.
      if (decision.outputs.some((output) => output._tag === "CatEntryAppended")) {
        await this.pushCatEntries();
      }
    }
    return decision;
  }

  /** Adopts the couple's cat, or renames it, and tells every socket that follows the journal. */
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
    }
    return decision;
  }

  /** Appends one journal entry and brings every socket that follows the journal up to date. */
  async recordCatEvent(by: UserId, request: RecordCatEventRequest): Promise<RoomDecision> {
    const decision = await this.run(
      (room) => room.recordCatEvent(by, request),
      "PairRoom.recordCatEvent",
    );
    if (decision._tag === "Accepted") await this.pushCatEntries();
    return decision;
  }

  /** The cat now, by the room's clock, or null while the room is not open. */
  cat(): Promise<CatResponse | null> {
    return this.run((room) => room.catView, "PairRoom.cat");
  }

  /** Journal entries with `seq` above `afterSeq`, in order. */
  catJournal(afterSeq: number, limit: number): Promise<ReadonlyArray<CatEntry>> {
    return this.run((room) => room.catEntriesAfter(afterSeq, limit), "PairRoom.catJournal");
  }

  /** Hands a note to every configured lane, once each, and makes sure the alarm will run. */
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

  private async scheduleAlarm(): Promise<void> {
    const entries = await Effect.runPromise(deliveriesOf(await this.database).all);
    const at = nextAlarmAt(entries);
    if (at !== undefined) await this.ctx.storage.setAlarm(at);
  }

  /** How each lane is doing in this room. */
  async deliveryHealth(): Promise<Readonly<Record<string, LaneHealth>>> {
    return deliveryHealth(await this.deliveries());
  }

  /** The delivery rows, for tests and diagnostics. */
  async deliveries(): Promise<ReadonlyArray<DeliveryEntry>> {
    return Effect.runPromise(deliveriesOf(await this.database).all);
  }

  /**
   * Works through the pending deliveries that are due, one try each. A sender that throws counts
   * as a retry, so a failing lane backs off instead of ending the alarm. Delivered and abandoned
   * entries are never sent again, which is what makes a repeated alarm harmless.
   */
  override async alarm(): Promise<void> {
    const sender = this.laneSender;
    if (sender === undefined) return;
    await traced("PairRoom.alarm", this.spanAttributes, async (context) => {
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
      await this.scheduleAlarm();
    });
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

  /** Notes with `seq` above `afterSeq`, in order. */
  /** The ink colours the pair bought, in the order it got them. The free ink is not listed. */
  inks(): Promise<ReadonlyArray<InkId>> {
    return this.run((room) =>
      room.state.pipe(Effect.map((state) => (state._tag === "Active" ? state.inks : []))),
    );
  }

  /** Gives the pair ink colours. The wallet calls it once it has taken their coins. */
  grantInks(inks: ReadonlyArray<InkId>): Promise<RoomDecision> {
    return this.run((room) => room.dispatch({ _tag: "GrantInks", inks }), "PairRoom.grantInks");
  }

  notes(afterSeq: number, limit: number): Promise<ReadonlyArray<SequencedNote>> {
    return this.run((room) => room.notesAfter(afterSeq, limit), "PairRoom.notes");
  }

  /**
   * The pair is ending because `user` is leaving: deletes every note they sent with its delivery
   * rows, and the cat with its whole journal, returns those notes so their images can go too, and
   * closes every socket of the room.
   * Repeating it finds nothing more to delete.
   */
  async forgetMember(user: UserId): Promise<ReadonlyArray<SequencedNote>> {
    const forgotten = await this.run((room) => room.forgetAuthor(user), "PairRoom.forgetMember");
    const deliveries = deliveriesOf(await this.database);
    for (const { note } of forgotten) await Effect.runPromise(deliveries.forget(note.id));
    for (const socket of this.ctx.getWebSockets()) {
      try {
        socket.close(1000, "pair ended");
      } catch {
        // Already closing: nothing left to end.
      }
    }
    return forgotten;
  }

  /**
   * Accepts a partner's hibernatable WebSocket. The object can leave memory while the socket stays
   * open, so an idle room costs nothing. Its messages are the relay in `webSocketMessage`.
   */
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
      if (partner !== undefined) send(server, { _tag: "Presence", state: partner.presence });
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  /**
   * One frame from a partner's device. Frames that are not text, too large, or not a
   * `ClientMessage` are dropped; an oversized one also ends the connection.
   */
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
        // Start from what the client holds, never from more than it asks for. A client that
        // leaves `lastCatSeq` out does not follow the cat's journal.
        const { lastSeq, lastCatSeq } = message.value;
        socket.serializeAttachment({
          ...attachment,
          sentSeq: Math.max(0, lastSeq),
          sentCatSeq: lastCatSeq === undefined ? null : Math.max(0, lastCatSeq),
        } satisfies SocketAttachment);
        await this.catchUp(socket);
        await this.catchUpCat(socket);
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
        this.toPartner(attachment.user, message.value);
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

  /** Tells the partner to discard the strokes a leaving socket left open. */
  private dropOpenStrokes(socket: WebSocket): void {
    const attachment = attachmentOf(socket);
    if (attachment === undefined) return;
    for (const id of attachment.openStrokes ?? []) {
      this.toPartner(attachment.user, { _tag: "StrokeDropped", id });
    }
    socket.serializeAttachment({ ...attachment, openStrokes: [] } satisfies SocketAttachment);
  }

  /** Sends one socket every stored note it has not seen, oldest first, without repeats. */
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

  /** Sends one socket every journal entry it has not seen, oldest first, without repeats. */
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

  /** After a journal entry is stored, brings every socket that follows the journal up to date. */
  private async pushCatEntries(): Promise<void> {
    await Promise.all(this.ctx.getWebSockets().map((socket) => this.catchUpCat(socket)));
  }

  /** After a note is stored, brings every resumed socket of the couple up to date. */
  private async pushNotes(): Promise<void> {
    await Promise.all(this.ctx.getWebSockets().map((socket) => this.catchUp(socket)));
  }

  private toPartner(user: string, message: ServerMessage): void {
    for (const socket of this.ctx.getWebSockets()) {
      if (attachmentOf(socket)?.user !== user) send(socket, message);
    }
  }

  /** The user has no open socket left: they cannot be drawing, so the partner is told they stopped. */
  private async leave(socket: WebSocket): Promise<void> {
    const user = attachmentOf(socket)?.user;
    if (user === undefined) return;
    const others = this.ctx.getWebSockets(user).filter((other) => other !== socket);
    if (others.some((other) => other.readyState === WebSocket.OPEN)) return;
    const room = await this.snapshot();
    if (room._tag !== "Active") return;
    if (room.members.find((member) => member.user === user)?.presence === "idle") return;
    const decision = await this.setPresence(user as UserId, "idle");
    if (decision._tag === "Accepted") this.toPartner(user, { _tag: "Presence", state: "idle" });
  }

  /**
   * Answers a client's close. 1006 and 1015 mean the connection is already gone, so there is
   * nothing to answer and `close` would throw. 1005 means no code was sent, and cannot be sent back.
   */
  override async webSocketClose(socket: WebSocket, code: number): Promise<void> {
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
