import { DurableObject } from "cloudflare:workers";
import { Effect, Layer, ManagedRuntime, Schema, Scope } from "effect";
import { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { SendNoteRequest } from "@billet/contracts-http-api/note";
import type { PresenceState } from "@billet/contracts-realtime/client-message";
import { isMember } from "@billet/backend-pair-room/decide";
import type { RoomDecision } from "@billet/backend-pair-room/room-decision";
import { RoomService } from "@billet/backend-pair-room/room-service";
import type { RoomState, SequencedNote } from "@billet/backend-pair-room/room-state";
import { PairRoomLive } from "./pair-room-runtime.ts";
import { RoomDb } from "./pair-room-sqlite-store.ts";
import { openRoomDatabase } from "./room-database.ts";

/** Who is connecting. Only the Worker can reach this object, after it has authenticated them. */
export const ROOM_USER_HEADER = "x-billet-user";

const decodeUser = Schema.decodeUnknownOption(UserId);

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
  private readonly runtime = this.ctx.blockConcurrencyWhile(async () => {
    const database = await Effect.runPromise(
      openRoomDatabase(this.ctx.storage).pipe(Scope.provide(Scope.makeUnsafe())),
    );
    return ManagedRuntime.make(PairRoomLive.pipe(Layer.provide(Layer.succeed(RoomDb, database))));
  });

  private async run<A>(program: (room: RoomService["Service"]) => Effect.Effect<A>): Promise<A> {
    return (await this.runtime).runPromise(RoomService.use(program));
  }

  open(pairId: PairId, members: readonly [UserId, UserId]): Promise<RoomDecision> {
    return this.run((room) => room.dispatch({ _tag: "Open", pairId, members }));
  }

  sendNote(author: UserId, request: SendNoteRequest): Promise<RoomDecision> {
    return this.run((room) => room.sendNote(author, request));
  }

  setPresence(user: UserId, state: PresenceState): Promise<RoomDecision> {
    return this.run((room) => room.dispatch({ _tag: "SetPresence", user, state }));
  }

  snapshot(): Promise<RoomState> {
    return this.run((room) => room.state);
  }

  /** Notes with `seq` above `afterSeq`, in order. */
  notes(afterSeq: number, limit: number): Promise<ReadonlyArray<SequencedNote>> {
    return this.run((room) => room.notesAfter(afterSeq, limit));
  }

  /**
   * Accepts a partner's hibernatable WebSocket. The object can leave memory while the socket stays
   * open, so an idle room costs nothing. Handling its messages is the relay, which is #17.
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
    return new Response(null, { status: 101, webSocket: client });
  }

  /**
   * Answers a client's close. 1006 and 1015 mean the connection is already gone, so there is
   * nothing to answer and `close` would throw. 1005 means no code was sent, and cannot be sent back.
   */
  override webSocketClose(socket: WebSocket, code: number): void {
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
