import { DurableObject } from "cloudflare:workers";
import {
  MAX_QUEUED_GIFTS,
  MAX_QUEUED_PETS,
  adoptFrame,
  giftFrame,
  type AdoptFrame,
  isTime,
  keepFirstName,
  parsePlay,
  recordLife,
  type LifeEvent,
  recordReaction,
  recordTreat,
  type QueuedGift,
  type QueuedPet,
  type Reactions,
  type RoomStyle,
  type TreatDays,
  dayOf,
  type DailyFrame,
  type PieceSpot,
} from "./demo-play.ts";
import { sendAlert, sendNoteAlert, type ApnsCredentials, type ApnsFetch } from "./demo-apns.ts";
import {
  MAX_CLOCK_SKEW_MS,
  addDays,
  dailyView,
  droppedDays,
  dueReminders,
  nextReminderAt,
  offsetOf,
  promptFor,
  promptsFrame,
  recordDaily,
  reminderText,
  type DailyDays,
  type DailyDrawing,
  type Reminded,
} from "./daily-drawing.ts";
import { traced } from "./demo-trace.ts";
import { systemNow } from "./wall-clock.ts";

export const MAX_FRAME_BYTES = 512 * 1024;
export const MAX_QUEUED_NOTES = 50;
export const DEVICE_HEADER = "x-demo-device";
/** Recent days of the drawing of the day a connecting phone is sent again. */
export const DAILY_REPLAY_DAYS = 7;
export const CODE_HEADER = "x-demo-code";

const CLOSE_TOO_BIG = 1009;

export interface DemoRoomEnv {
  readonly APNS_KEY?: string;
  readonly APNS_KEY_ID?: string;
}

const ARRANGEMENT_PREFIX = "arrangement:";
/** Every furniture set, plain and with Idol props. */
export const MAX_ARRANGED_ROOMS = 24;

const NOTE_PATH = /^\/demo\/rooms\/[^/]+\/notes\/([^/]+)$/;
const PLAYS_PATH = /^\/demo\/rooms\/[^/]+\/plays$/;
/** A widget's treat is a treat and a feed. */
export const MAX_POSTED_PLAYS = 2;
export const MAX_POSTED_BYTES = 2048;
const POSTABLE_KINDS: ReadonlySet<unknown> = new Set(["pet", "treat", "feed"]);
const TOKEN = /^[0-9a-fA-F]{32,200}$/;

interface QueuedNote {
  readonly id: string;
  readonly ink: string;
  readonly from: string;
  readonly to: string;
}

const UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

const petFrame = (pet: QueuedPet) => ({
  type: "play",
  id: pet.id,
  kind: pet.kind,
  at: pet.at,
  from: pet.from,
});

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null;

/** Undelivered notes live in key-value storage; hibernatable sockets are tagged by device id. */
export class DemoRoom extends DurableObject<DemoRoomEnv> {
  protected apnsFetch: ApnsFetch = (url, init) => fetch(url, init);

  protected clock(): number {
    return systemNow();
  }

  /** By the start of the object id, never by the room's code. */
  private readonly spanAttributes = { "room.ref": this.ctx.id.toString().slice(0, 16) };

  protected apnsCredentials(): Promise<ApnsCredentials | undefined> {
    const { APNS_KEY: key, APNS_KEY_ID: keyId } = this.env;
    return Promise.resolve(key === undefined || keyId === undefined ? undefined : { key, keyId });
  }

  override fetch(request: Request): Promise<Response> {
    return traced("DemoRoom.fetch", this.spanAttributes, () => this.respond(request));
  }

  private async respond(request: Request): Promise<Response> {
    const device = request.headers.get(DEVICE_HEADER);
    if (device === null || !UUID.test(device)) return new Response(null, { status: 400 });
    const id = device.toLowerCase();
    const url = new URL(request.url);
    const noteMatch = NOTE_PATH.exec(url.pathname);
    if (noteMatch !== null) return this.readNote(id, (noteMatch[1] ?? "").toLowerCase());
    if (PLAYS_PATH.test(url.pathname)) return this.postPlays(id, request);
    if (request.headers.get("Upgrade") !== "websocket") return new Response(null, { status: 426 });
    const code = request.headers.get(CODE_HEADER);
    if (code !== null) await this.ctx.storage.put("code", code);
    await this.ctx.storage.put("origin", url.origin);

    const devices = (await this.ctx.storage.get<string[]>("devices")) ?? [];
    if (!devices.includes(id)) {
      if (devices.length >= 2) return new Response(null, { status: 403 });
      await this.ctx.storage.put("devices", [...devices, id]);
    }

    const { 0: client, 1: server } = new WebSocketPair();
    this.ctx.acceptWebSocket(server, [id]);
    await this.replay(server, id);
    await this.replayPlay(server, id);
    await this.replayDaily(server, id);
    this.announcePresence();
    return new Response(null, { status: 101, webSocket: client });
  }

  override async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const size =
      typeof message === "string" ? new TextEncoder().encode(message).length : message.byteLength;
    if (size > MAX_FRAME_BYTES) {
      socket.close(CLOSE_TOO_BIG, "frame too large");
      return;
    }
    if (typeof message !== "string") return;
    const [sender] = this.ctx.getTags(socket);
    if (sender === undefined) return;

    let frame: unknown;
    try {
      frame = JSON.parse(message);
    } catch {
      return;
    }
    if (!isRecord(frame)) return;
    if (frame["type"] === "push-token") {
      const token = frame["token"];
      if (typeof token !== "string" || !TOKEN.test(token)) return;
      const tokens = (await this.ctx.storage.get<Record<string, string>>("tokens")) ?? {};
      await this.ctx.storage.put("tokens", {
        ...tokens,
        [sender]: token.toLowerCase(),
      });
      return;
    }
    if (frame["type"] === "play") {
      const acked = await traced(
        "DemoRoom.play",
        { ...this.spanAttributes, "play.kind": String(frame["kind"] ?? "unknown") },
        () => this.handlePlay(sender, frame),
      );
      if (acked !== undefined) socket.send(JSON.stringify({ type: "ack", id: acked }));
      return;
    }
    if (frame["type"] !== "note") return;
    await traced("DemoRoom.note", this.spanAttributes, () =>
      this.handleNote(socket, sender, frame),
    );
  }

  /** A repeated note is only acked. */
  private async handleNote(
    socket: WebSocket,
    sender: string,
    frame: Readonly<Record<string, unknown>>,
  ): Promise<void> {
    const { id, ink } = frame;
    if (typeof id !== "string" || !UUID.test(id) || typeof ink !== "string") return;

    const devices = (await this.ctx.storage.get<string[]>("devices")) ?? [];
    const partner = devices.find((d) => d !== sender);
    const seen = (await this.ctx.storage.get<string[]>("seen")) ?? [];
    if (!seen.includes(id)) {
      await this.ctx.storage.put("seen", [...seen, id].slice(-200));
      const senders = (await this.ctx.storage.get<Record<string, string>>("noteFrom")) ?? {};
      await this.ctx.storage.put(
        "noteFrom",
        Object.fromEntries(Object.entries({ ...senders, [id.toLowerCase()]: sender }).slice(-200)),
      );
      const queued =
        partner === undefined
          ? undefined
          : await this.deliverOrQueue({ id, ink, from: sender, to: partner });
      const at = frame["at"];
      if (isTime(at)) await this.recordOffset(sender, at);
      await this.recordLife({
        id: id.toLowerCase(),
        kind: "note",
        by: sender,
        at: isTime(at) ? at : new Date(this.clock()).toISOString(),
      });
      socket.send(JSON.stringify({ type: "ack", id }));
      // The ack means "stored"; it must not wait on APNs, which is external and can stall.
      if (queued !== undefined) this.ctx.waitUntil(this.alertPartner(queued));
      return;
    }
    socket.send(JSON.stringify({ type: "ack", id }));
  }

  override webSocketClose(socket: WebSocket, code: number): void {
    if (code !== 1006 && code !== 1015) socket.close(code === 1005 ? 1000 : code);
    this.announcePresence(socket);
  }

  override webSocketError(socket: WebSocket): void {
    this.announcePresence(socket);
  }

  /** Adopt picks, light, style and arrangements are replayed on connect; only a receiver reacts. */
  private async handlePlay(
    sender: string,
    frame: Readonly<Record<string, unknown>>,
  ): Promise<string | undefined> {
    const play = parsePlay(frame);
    if (play === undefined) return undefined;
    await this.recordOffset(sender, play.at);
    const seen = (await this.ctx.storage.get<string[]>("seen")) ?? [];
    if (!seen.includes(play.id)) {
      await this.ctx.storage.put("seen", [...seen, play.id].slice(-200));
      if (play.kind === "treat") {
        const days = (await this.ctx.storage.get<TreatDays>("treatDays")) ?? {};
        await this.ctx.storage.put("treatDays", recordTreat(days, sender, play.at));
        await this.broadcastTreats();
      } else if (play.kind === "name") {
        const current = await this.ctx.storage.get<string>("catName");
        const name = keepFirstName(current, play.name);
        if (current === undefined) await this.ctx.storage.put("catName", name);
        this.broadcast({ type: "name", name });
      } else if (play.kind === "rename") {
        await this.ctx.storage.put("catName", play.name);
        this.broadcast({ type: "name", name: play.name });
      } else if (play.kind === "daily") {
        await this.recordDailyDrawing(sender, play);
      } else if (play.kind === "adopt") {
        await this.relayAdopt(sender, play);
      } else if (play.kind === "light") {
        await this.ctx.storage.put("roomLight", play.light);
        this.broadcast({ type: "light", light: play.light });
      } else if (play.kind === "style") {
        await this.ctx.storage.put("roomStyle", play.style);
        this.broadcast({ type: "style", style: play.style });
      } else if (play.kind === "arrange") {
        const key = `${ARRANGEMENT_PREFIX}${play.room}`;
        const known = await this.ctx.storage.list({ prefix: ARRANGEMENT_PREFIX });
        if (known.has(key) || known.size < MAX_ARRANGED_ROOMS) {
          await this.ctx.storage.put(key, play.spots);
          this.broadcast({ type: "arrange", room: play.room, spots: play.spots });
        }
      } else if (play.kind === "react") {
        const senders = (await this.ctx.storage.get<Record<string, string>>("noteFrom")) ?? {};
        const author = senders[play.note];
        if (author !== undefined && author !== sender) {
          const reactions = (await this.ctx.storage.get<Reactions>("reactions")) ?? {};
          await this.ctx.storage.put(
            "reactions",
            recordReaction(reactions, play.note, play.reaction),
          );
          await this.broadcastReactions();
        }
      } else if (play.kind === "gift" || play.kind === "gift-opened") {
        const devices = (await this.ctx.storage.get<string[]>("devices")) ?? [];
        const partner = devices.find((d) => d !== sender);
        if (partner !== undefined) await this.relayGift({ ...play, from: sender, to: partner });
      } else if (play.kind === "pet") {
        const devices = (await this.ctx.storage.get<string[]>("devices")) ?? [];
        const partner = devices.find((d) => d !== sender);
        if (partner !== undefined) {
          await this.relayPet({
            ...play,
            kind: "pet",
            from: sender,
            to: partner,
          });
        }
        await this.recordLife({
          id: play.id.toLowerCase(),
          kind: "pet",
          by: sender,
          at: play.at,
        });
      } else {
        await this.recordLife({
          id: play.id.toLowerCase(),
          kind: play.kind,
          by: sender,
          at: play.at,
        });
      }
    }
    return play.id;
  }

  /** A widget's plays: queued notes and pets stay queued and no presence is announced. */
  private async postPlays(device: string, request: Request): Promise<Response> {
    const devices = (await this.ctx.storage.get<string[]>("devices")) ?? [];
    if (!devices.includes(device)) return new Response(null, { status: 404 });
    const text = await request.text();
    if (new TextEncoder().encode(text).length > MAX_POSTED_BYTES) {
      return new Response(null, { status: 413 });
    }
    let body: unknown;
    try {
      body = JSON.parse(text);
    } catch {
      return new Response(null, { status: 400 });
    }
    if (!Array.isArray(body) || body.length === 0 || body.length > MAX_POSTED_PLAYS) {
      return new Response(null, { status: 400 });
    }
    const frames: Array<Readonly<Record<string, unknown>>> = body.filter(isRecord);
    const valid = frames.every(
      (frame) => POSTABLE_KINDS.has(frame["kind"]) && parsePlay(frame) !== undefined,
    );
    if (frames.length !== body.length || !valid) return new Response(null, { status: 400 });
    for (const frame of frames) await this.handlePlay(device, frame);
    return new Response(null, { status: 204 });
  }

  /** Seeded by the room's code, or its id before it has one. */
  private async pairKey(): Promise<string> {
    return (await this.ctx.storage.get<string>("code")) ?? this.ctx.id.toString();
  }

  private async dailyDrawings(day: string): Promise<Record<string, DailyDrawing>> {
    const days = (await this.ctx.storage.get<DailyDays>("dailyDays")) ?? {};
    const drew = days[day] ?? [];
    const stored = await this.ctx.storage.get<DailyDrawing>(drew.map((d) => `daily:${day}:${d}`));
    return Object.fromEntries(
      drew.flatMap((device) => {
        const drawing = stored.get(`daily:${day}:${device}`);
        return drawing === undefined ? [] : [[device, drawing]];
      }),
    );
  }

  /** A second drawing of a day changes nothing, so nobody can peek at the partner's and redraw. */
  private async recordDailyDrawing(sender: string, play: DailyFrame): Promise<void> {
    if (Math.abs(Date.parse(play.at) - this.clock()) > MAX_CLOCK_SKEW_MS) return;
    const day = dayOf(play.at);
    const days = (await this.ctx.storage.get<DailyDays>("dailyDays")) ?? {};
    const next = recordDaily(days, sender, day);
    if (next !== days) {
      await this.ctx.storage.put(`daily:${day}:${sender}`, {
        id: play.id.toLowerCase(),
        ink: play.ink,
        at: play.at,
      } satisfies DailyDrawing);
      const dropped = droppedDays(days, next).flatMap((d) =>
        (days[d] ?? []).map((device) => `daily:${d}:${device}`),
      );
      if (dropped.length > 0) await this.ctx.storage.delete(dropped);
      await this.ctx.storage.put("dailyDays", next);
    }
    await this.sendDailyViews(day);
    await this.scheduleReminder();
  }

  private async sendDailyViews(day: string): Promise<void> {
    const pair = await this.pairKey();
    const drawings = await this.dailyDrawings(day);
    for (const socket of this.ctx.getWebSockets()) {
      const [device] = this.ctx.getTags(socket);
      if (device === undefined) continue;
      socket.send(JSON.stringify(dailyView(pair, day, device, drawings)));
    }
  }

  private async replayDaily(socket: WebSocket, device: string): Promise<void> {
    const pair = await this.pairKey();
    const now = this.clock();
    socket.send(JSON.stringify(promptsFrame(pair, now)));
    const days = (await this.ctx.storage.get<DailyDays>("dailyDays")) ?? {};
    const oldest = addDays(new Date(now).toISOString().slice(0, 10), -DAILY_REPLAY_DAYS);
    for (const day of Object.keys(days).sort()) {
      if (day < oldest) continue;
      socket.send(JSON.stringify(dailyView(pair, day, device, await this.dailyDrawings(day))));
    }
  }

  /** The offset says when the phone's evening is. */
  private async recordOffset(device: string, at: string): Promise<void> {
    const offset = offsetOf(at);
    if (offset === undefined) return;
    const offsets = (await this.ctx.storage.get<Record<string, number>>("offsets")) ?? {};
    if (offsets[device] === offset) return;
    await this.ctx.storage.put("offsets", { ...offsets, [device]: offset });
    await this.scheduleReminder();
  }

  private async reminderInputs() {
    return {
      devices: (await this.ctx.storage.get<string[]>("devices")) ?? [],
      offsets: (await this.ctx.storage.get<Record<string, number>>("offsets")) ?? {},
      reminded: (await this.ctx.storage.get<Reminded>("dailyReminded")) ?? {},
      days: (await this.ctx.storage.get<DailyDays>("dailyDays")) ?? {},
    };
  }

  private async scheduleReminder(): Promise<void> {
    const at = nextReminderAt(this.clock(), await this.reminderInputs());
    if (at === undefined) {
      await this.ctx.storage.deleteAlarm();
      return;
    }
    const current = await this.ctx.storage.getAlarm();
    if (current !== at) await this.ctx.storage.setAlarm(at);
  }

  /** Never in quiet hours; a tokenless phone counts as reminded, so no late push follows. */
  override alarm(): Promise<void> {
    return traced("DemoRoom.alarm", this.spanAttributes, () => this.remind());
  }

  private async remind(): Promise<void> {
    const now = this.clock();
    const inputs = await this.reminderInputs();
    const due = dueReminders(now, inputs);
    if (due.length > 0) {
      const reminded = { ...inputs.reminded };
      for (const { device, day } of due) reminded[device] = day;
      await this.ctx.storage.put("dailyReminded", reminded);
      const credentials = await this.apnsCredentials();
      const tokens = (await this.ctx.storage.get<Record<string, string>>("tokens")) ?? {};
      const catName = await this.ctx.storage.get<string>("catName");
      const pair = await this.pairKey();
      for (const { device, day, partnerDrew } of due) {
        const token = tokens[device];
        if (credentials === undefined || token === undefined) continue;
        const body = reminderText(catName, promptFor(pair, day), partnerDrew);
        await sendAlert(
          credentials,
          token,
          { aps: { alert: { body } }, daily: day },
          this.apnsFetch,
          () => this.clock(),
        );
      }
    }
    await this.scheduleReminder();
  }

  private async recordLife(event: LifeEvent): Promise<void> {
    const log = (await this.ctx.storage.get<readonly LifeEvent[]>("life")) ?? [];
    const next = recordLife(log, event);
    if (next === log) return;
    await this.ctx.storage.put("life", next);
    this.broadcast({ type: "life", events: [event] });
  }

  private async relayAdopt(sender: string, play: AdoptFrame): Promise<void> {
    if (play.move === "pick") {
      const picks = (await this.ctx.storage.get<Record<string, AdoptFrame>>("adoptPicks")) ?? {};
      await this.ctx.storage.put("adoptPicks", { ...picks, [sender]: play });
    } else if (play.move === "adopt") {
      await this.ctx.storage.put("adopted", play);
    }
    const devices = (await this.ctx.storage.get<string[]>("devices")) ?? [];
    const partner = devices.find((d) => d !== sender);
    if (partner === undefined) return;
    const [target] = this.ctx.getWebSockets(partner);
    target?.send(JSON.stringify(adoptFrame(play)));
  }

  private async relayGift(gift: QueuedGift): Promise<void> {
    const [target] = this.ctx.getWebSockets(gift.to);
    if (target !== undefined) {
      target.send(JSON.stringify(giftFrame(gift)));
      return;
    }
    const queue = (await this.ctx.storage.get<QueuedGift[]>("gifts")) ?? [];
    await this.ctx.storage.put("gifts", [...queue, gift].slice(-MAX_QUEUED_GIFTS));
  }

  private async relayPet(pet: QueuedPet): Promise<void> {
    const [target] = this.ctx.getWebSockets(pet.to);
    if (target !== undefined) {
      target.send(JSON.stringify(petFrame(pet)));
      return;
    }
    const queue = (await this.ctx.storage.get<QueuedPet[]>("pets")) ?? [];
    await this.ctx.storage.put("pets", [...queue, pet].slice(-MAX_QUEUED_PETS));
  }

  private async replayPlay(socket: WebSocket, device: string): Promise<void> {
    const days = (await this.ctx.storage.get<TreatDays>("treatDays")) ?? {};
    socket.send(JSON.stringify({ type: "treats", days }));
    const name = await this.ctx.storage.get<string>("catName");
    if (name !== undefined) socket.send(JSON.stringify({ type: "name", name }));
    const light = await this.ctx.storage.get<string>("roomLight");
    if (light !== undefined) socket.send(JSON.stringify({ type: "light", light }));
    const style = await this.ctx.storage.get<RoomStyle>("roomStyle");
    if (style !== undefined) socket.send(JSON.stringify({ type: "style", style }));
    const arrangements = await this.ctx.storage.list<Record<string, PieceSpot>>({
      prefix: ARRANGEMENT_PREFIX,
    });
    for (const [key, spots] of arrangements) {
      const room = key.slice(ARRANGEMENT_PREFIX.length);
      socket.send(JSON.stringify({ type: "arrange", room, spots }));
    }
    const reactions = (await this.ctx.storage.get<Reactions>("reactions")) ?? {};
    if (Object.keys(reactions).length > 0) {
      socket.send(JSON.stringify({ type: "reactions", reactions }));
    }
    const life = (await this.ctx.storage.get<readonly LifeEvent[]>("life")) ?? [];
    if (life.length > 0) socket.send(JSON.stringify({ type: "life", events: life }));
    const picks = (await this.ctx.storage.get<Record<string, AdoptFrame>>("adoptPicks")) ?? {};
    for (const [from, pick] of Object.entries(picks)) {
      if (from !== device) socket.send(JSON.stringify(adoptFrame(pick)));
    }
    const adopted = await this.ctx.storage.get<AdoptFrame>("adopted");
    if (adopted !== undefined) socket.send(JSON.stringify(adoptFrame(adopted)));
    const gifts = (await this.ctx.storage.get<QueuedGift[]>("gifts")) ?? [];
    const giftsForMe = gifts.filter((g) => g.to === device);
    if (giftsForMe.length > 0) {
      await this.ctx.storage.put(
        "gifts",
        gifts.filter((g) => g.to !== device),
      );
      for (const gift of giftsForMe) socket.send(JSON.stringify(giftFrame(gift)));
    }
    const queue = (await this.ctx.storage.get<QueuedPet[]>("pets")) ?? [];
    const mine = queue.filter((p) => p.to === device);
    if (mine.length === 0) return;
    await this.ctx.storage.put(
      "pets",
      queue.filter((p) => p.to !== device),
    );
    for (const pet of mine) socket.send(JSON.stringify(petFrame(pet)));
  }

  private async broadcastTreats(): Promise<void> {
    const days = (await this.ctx.storage.get<TreatDays>("treatDays")) ?? {};
    this.broadcast({ type: "treats", days });
  }

  private async broadcastReactions(): Promise<void> {
    const reactions = (await this.ctx.storage.get<Reactions>("reactions")) ?? {};
    this.broadcast({ type: "reactions", reactions });
  }

  private broadcast(frame: Readonly<Record<string, unknown>>): void {
    const message = JSON.stringify(frame);
    for (const socket of this.ctx.getWebSockets()) socket.send(message);
  }

  /** Resolves to the note only when it was queued because the partner has no open socket. */
  private async deliverOrQueue(note: QueuedNote): Promise<QueuedNote | undefined> {
    const [target] = this.ctx.getWebSockets(note.to);
    if (target !== undefined) {
      target.send(
        JSON.stringify({
          type: "note",
          id: note.id,
          ink: note.ink,
          from: note.from,
        }),
      );
      return undefined;
    }
    const queue = (await this.ctx.storage.get<QueuedNote[]>("queue")) ?? [];
    await this.ctx.storage.put("queue", [...queue, note].slice(-MAX_QUEUED_NOTES));
    return note;
  }

  private alertPartner(note: QueuedNote): Promise<void> {
    return traced("DemoRoom.alertPartner", this.spanAttributes, () => this.sendAlert(note));
  }

  private async sendAlert(note: QueuedNote): Promise<void> {
    const credentials = await this.apnsCredentials();
    if (credentials === undefined) return;
    const tokens = (await this.ctx.storage.get<Record<string, string>>("tokens")) ?? {};
    const token = tokens[note.to];
    const code = await this.ctx.storage.get<string>("code");
    const origin = await this.ctx.storage.get<string>("origin");
    if (token === undefined || code === undefined || origin === undefined) return;
    const noteURL = `${origin}/demo/rooms/${code}/notes/${note.id}`;
    await sendNoteAlert(credentials, token, noteURL, this.apnsFetch, () => this.clock());
  }

  private async readNote(device: string, noteId: string): Promise<Response> {
    const devices = (await this.ctx.storage.get<string[]>("devices")) ?? [];
    if (!devices.includes(device)) return new Response(null, { status: 404 });
    const queue = (await this.ctx.storage.get<QueuedNote[]>("queue")) ?? [];
    const note = queue.find((n) => n.to === device && n.id.toLowerCase() === noteId);
    if (note === undefined) return new Response(null, { status: 404 });
    return Response.json({ id: note.id, ink: note.ink, from: note.from });
  }

  private async replay(socket: WebSocket, device: string): Promise<void> {
    const queue = (await this.ctx.storage.get<QueuedNote[]>("queue")) ?? [];
    const mine = queue.filter((n) => n.to === device);
    if (mine.length === 0) return;
    await this.ctx.storage.put(
      "queue",
      queue.filter((n) => n.to !== device),
    );
    for (const n of mine) {
      socket.send(JSON.stringify({ type: "note", id: n.id, ink: n.ink, from: n.from }));
    }
  }

  private announcePresence(closing?: WebSocket): void {
    const sockets = this.ctx.getWebSockets().filter((s) => s !== closing);
    for (const socket of sockets) {
      const [me] = this.ctx.getTags(socket);
      const partnerPresent = sockets.some((s) => this.ctx.getTags(s)[0] !== me);
      socket.send(JSON.stringify({ type: "room", partnerPresent }));
    }
  }
}
