import { DurableObject } from "cloudflare:workers";

export const MAX_FRAME_BYTES = 512 * 1024;
export const MAX_QUEUED_NOTES = 50;
export const DEVICE_HEADER = "x-demo-device";

const CLOSE_TOO_BIG = 1009;

interface QueuedNote {
  readonly id: string;
  readonly ink: string;
  readonly from: string;
  readonly to: string;
}

const UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null;

/**
 * Temporary demo room: two anonymous devices exchange notes. Undelivered notes live in the
 * object's key-value storage; sockets are hibernatable and tagged with their device id.
 */
export class DemoRoom extends DurableObject {
  override async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade") !== "websocket") return new Response(null, { status: 426 });
    const device = request.headers.get(DEVICE_HEADER);
    if (device === null || !UUID.test(device)) return new Response(null, { status: 400 });
    const id = device.toLowerCase();

    const devices = (await this.ctx.storage.get<string[]>("devices")) ?? [];
    if (!devices.includes(id)) {
      if (devices.length >= 2) return new Response(null, { status: 403 });
      await this.ctx.storage.put("devices", [...devices, id]);
    }

    const { 0: client, 1: server } = new WebSocketPair();
    this.ctx.acceptWebSocket(server, [id]);
    await this.replay(server, id);
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
    if (!isRecord(frame) || frame["type"] !== "note") return;
    const { id, ink } = frame;
    if (typeof id !== "string" || !UUID.test(id) || typeof ink !== "string") return;

    const devices = (await this.ctx.storage.get<string[]>("devices")) ?? [];
    const partner = devices.find((d) => d !== sender);
    const seen = (await this.ctx.storage.get<string[]>("seen")) ?? [];
    if (!seen.includes(id)) {
      await this.ctx.storage.put("seen", [...seen, id].slice(-200));
      if (partner !== undefined) await this.deliverOrQueue({ id, ink, from: sender, to: partner });
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

  private async deliverOrQueue(note: QueuedNote): Promise<void> {
    const [target] = this.ctx.getWebSockets(note.to);
    if (target !== undefined) {
      target.send(JSON.stringify({ type: "note", id: note.id, ink: note.ink, from: note.from }));
      return;
    }
    const queue = (await this.ctx.storage.get<QueuedNote[]>("queue")) ?? [];
    await this.ctx.storage.put("queue", [...queue, note].slice(-MAX_QUEUED_NOTES));
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
