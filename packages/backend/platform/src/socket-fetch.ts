import { Effect, Layer, Option, Redacted } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import { AuthService } from "@billet/backend-auth/auth-service";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { authorizationHeader, bearerPrefix } from "@billet/contracts-http-api/routes";
import { AppleIdentityLive } from "./apple-identity-live.ts";
import { AuthRepositoryLive } from "./auth-repository-live.ts";
import { BetterAuthEngineLive } from "./better-auth-engine.ts";
import { PairingRepositoryLive } from "./pairing-repository-live.ts";
import { ROOM_USER_HEADER } from "./pair-room-durable-object.ts";
import type { WorkerEnv } from "./worker-env.ts";

const refuse = (status: number) => new Response(null, { status });

/** Who is on the other end, and which room is theirs: both come from D1, never from the client. */
const whoIsAsking = (env: WorkerEnv, token: Redacted.Redacted<string>) =>
  Effect.gen(function* () {
    const auth = yield* AuthService;
    const pairing = yield* PairingRepository;
    const { userId } = yield* auth.authenticate(token);
    const pairId = yield* pairing.findPair(userId);
    if (Option.isNone(pairId)) return Option.none();
    const members = yield* pairing.findMembers(pairId.value);
    return Option.some({ userId, pairId: pairId.value, members });
  }).pipe(
    Effect.provide(
      Layer.mergeAll(AuthService.layer, PairingRepositoryLive(env.DB)).pipe(
        Layer.provideMerge(
          Layer.mergeAll(
            AuthRepositoryLive(env.DB),
            BetterAuthEngineLive(env.DB),
            AppleIdentityLive,
            Digest.layerWebCrypto,
            SecureRandom.layerWebCrypto,
          ),
        ),
      ),
    ),
    Effect.scoped,
  );

/**
 * `GET /v1/socket`: authenticates the bearer token, finds the caller's pair and hands the upgrade
 * to that pair's `PairRoom`. The room opens on the first connection, because pairing commits in D1
 * and never reaches the room. The user header is set here and nowhere else.
 */
export const respondSocket = async (request: Request, env: WorkerEnv): Promise<Response> => {
  if (request.method !== "GET") return refuse(405);
  if (request.headers.get("Upgrade") !== "websocket") return refuse(426);
  const header = request.headers.get(authorizationHeader);
  if (header === null || !header.startsWith(bearerPrefix)) return refuse(401);

  const found = await Effect.runPromise(
    whoIsAsking(env, Redacted.make(header.slice(bearerPrefix.length))).pipe(
      Effect.map((asking) => ({ _tag: "Found" as const, asking })),
      Effect.catchTags({
        AuthRejected: () => Effect.succeed({ _tag: "Rejected" as const }),
      }),
      Effect.catch(() => Effect.succeed({ _tag: "Unavailable" as const })),
    ),
  );
  if (found._tag === "Rejected") return refuse(401);
  if (found._tag === "Unavailable") return refuse(503);
  if (Option.isNone(found.asking)) return refuse(404);

  const { userId, pairId, members } = found.asking.value;
  const [first, second] = members;
  if (first === undefined || second === undefined) return refuse(404);

  const room = env.PAIR_ROOM.getByName(pairId);
  await room.open(pairId, [first, second]);
  const headers = new Headers(request.headers);
  headers.delete(authorizationHeader);
  headers.set(ROOM_USER_HEADER, userId);
  return room.fetch(new Request(request.url, { headers }));
};
