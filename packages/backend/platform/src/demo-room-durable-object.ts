import { DurableObject } from "cloudflare:workers";
import {
  MAX_QUEUED_PETS,
  parsePlay,
  recordTreat,
  type PlayFrame,
  type QueuedPet,
  type TreatDays,
} from "./demo-play.ts";
import { sendNoteAlert, type ApnsCredentials, type ApnsFetch } from "./demo-apns.ts";

export const MAX_FRAME_BYTES = 512 * 1024;
export const MAX_QUEUED_NOTES = 50;
export const DEVICE_HEADER = "x-demo-device";
export const CODE_HEADER = "x-demo-code";

const CLOSE_TOO_BIG = 1009;

export interface DemoRoomEnv {
  readonly APNS_KEY?: string;
  readonly APNS_KEY_ID?: string;
}

const NOTE_PATH = /^\/demo\/rooms\/[^/]+\/notes\/([^/]+)$/;
const TOKEN = /^[0-9a-fA-F]{32,200}$/;

interface QueuedNote {
  readonly id: string;
  readonly ink: string;
  readonly from: string;
  readonly to: string;
}

const UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

const petFrame = (pet: PlayFrame & { readonly from: string }) => ({
  type: "play",
  id: pet.id,
  kind: pet.kind,
  at: pet.at,
  from: pet.from,
});

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null;

/**
 * Temporary demo room: two anonymous devices exchange notes. Undelivered notes live in the
 * object's key-value storage; sockets are hibernatable and tagged with their device id.
 */
export class DemoRoom extends DurableObject<DemoRoomEnv> {
  /** APNs transport; tests replace it with a stub. */
  protected apnsFetch: ApnsFetch = (url, init) => fetch(url, init);

  protected apnsCredentials(): Promise<ApnsCredentials | undefined> {
    const { APNS_KEY: key, APNS_KEY_ID: keyId } = this.env;
    return Promise.resolve(key === undefined || keyId === undefined ? undefined : { key, keyId });
  }

  override async fetch(request: Request): Promise<Response> {
    const device = request.headers.get(DEVICE_HEADER);
    if (device === null || !UUID.test(device)) return new Response(null, { status: 400 });
    const id = device.toLowerCase();
    const url = new URL(request.url);
    const noteMatch = NOTE_PATH.exec(url.pathname);
    if (noteMatch !== null) return this.readNote(id, (noteMatch[1] ?? "").toLowerCase());
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
      await this.ctx.storage.put("tokens", { ...tokens, [sender]: token.toLowerCase() });
      return;
    }
    if (frame["type"] === "play") {
      await this.handlePlay(socket, sender, frame);
      return;
    }
    if (frame["type"] !== "note") return;
    const { id, ink } = frame;
    if (typeof id !== "string" || !UUID.test(id) || typeof ink !== "string") return;

    const devices = (await this.ctx.storage.get<string[]>("devices")) ?? [];
    const partner = devices.find((d) => d !== sender);
    const seen = (await this.ctx.storage.get<string[]>("seen")) ?? [];
    if (!seen.includes(id)) {
      await this.ctx.storage.put("seen", [...seen, id].slice(-200));
      const queued =
        partner === undefined
          ? undefined
          : await this.deliverOrQueue({ id, ink, from: sender, to: partner });
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

  /**
   * A pet is relayed to the partner, or kept (newest few) until they connect. A treat is recorded
   * once per device per day, and the whole ledger goes to both sockets so phones agree.
   */
  private async handlePlay(
    socket: WebSocket,
    sender: string,
    frame: Readonly<Record<string, unknown>>,
  ): Promise<void> {
    const play = parsePlay(frame);
    if (play === undefined) return;
    const seen = (await this.ctx.storage.get<string[]>("seen")) ?? [];
    if (!seen.includes(play.id)) {
      await this.ctx.storage.put("seen", [...seen, play.id].slice(-200));
      if (play.kind === "treat") {
        const days = (await this.ctx.storage.get<TreatDays>("treatDays")) ?? {};
        await this.ctx.storage.put("treatDays", recordTreat(days, sender, play.at));
        await this.broadcastTreats();
      } else {
        const devices = (await this.ctx.storage.get<string[]>("devices")) ?? [];
        const partner = devices.find((d) => d !== sender);
        if (partner !== undefined) await this.relayPet({ ...play, from: sender, to: partner });
      }
    }
    socket.send(JSON.stringify({ type: "ack", id: play.id }));
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
    const message = JSON.stringify({ type: "treats", days });
    for (const socket of this.ctx.getWebSockets()) socket.send(message);
  }

  /** Resolves to the note when it was queued because the partner has no open socket. */
  private async deliverOrQueue(note: QueuedNote): Promise<QueuedNote | undefined> {
    const [target] = this.ctx.getWebSockets(note.to);
    if (target !== undefined) {
      target.send(JSON.stringify({ type: "note", id: note.id, ink: note.ink, from: note.from }));
      return undefined;
    }
    const queue = (await this.ctx.storage.get<QueuedNote[]>("queue")) ?? [];
    await this.ctx.storage.put("queue", [...queue, note].slice(-MAX_QUEUED_NOTES));
    return note;
  }

  private async alertPartner(note: QueuedNote): Promise<void> {
    const credentials = await this.apnsCredentials();
    if (credentials === undefined) return;
    const tokens = (await this.ctx.storage.get<Record<string, string>>("tokens")) ?? {};
    const token = tokens[note.to];
    const code = await this.ctx.storage.get<string>("code");
    const origin = await this.ctx.storage.get<string>("origin");
    if (token === undefined || code === undefined || origin === undefined) return;
    const noteURL = `${origin}/demo/rooms/${code}/notes/${note.id}`;
    await sendNoteAlert(credentials, token, noteURL, this.apnsFetch);
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
