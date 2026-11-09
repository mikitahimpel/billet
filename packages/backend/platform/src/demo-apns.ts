import { appleTeamId, signEs256 } from "./es256-jwt.ts";
import { logLine } from "./demo-trace.ts";
import { type Now, systemNow } from "./wall-clock.ts";

// One HTTP/2 request, no retries, no token cleanup.
export const APNS_TOPIC = "com.mikitahimpel.billet";
export const APNS_TEAM_ID = appleTeamId;
const APNS_ORIGIN = "https://api.push.apple.com";

export interface ApnsCredentials {
  readonly key: string;
  readonly keyId: string;
}

export type ApnsFetch = (url: string, init: RequestInit) => Promise<Response>;

const providerToken = ({ key, keyId }: ApnsCredentials, now: Now): Promise<string> =>
  signEs256({ pem: key, keyId }, { iss: APNS_TEAM_ID, iat: Math.floor(now() / 1000) });

/** Never throws, never logs the token. */
export const sendNoteAlert = (
  credentials: ApnsCredentials,
  deviceToken: string,
  noteURL: string,
  send: ApnsFetch = fetch,
  now: Now = systemNow,
): Promise<boolean> =>
  sendAlert(
    credentials,
    deviceToken,
    { aps: { alert: { body: "New note" }, "mutable-content": 1 }, noteURL },
    send,
    now,
  );

/** Never throws. */
export const sendAlert = async (
  credentials: ApnsCredentials,
  deviceToken: string,
  payload: Readonly<Record<string, unknown>>,
  send: ApnsFetch = fetch,
  now: Now = systemNow,
): Promise<boolean> => {
  try {
    const response = await send(`${APNS_ORIGIN}/3/device/${deviceToken}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${await providerToken(credentials, now)}`,
        "apns-topic": APNS_TOPIC,
        "apns-push-type": "alert",
        "apns-priority": "10",
      },
      body: JSON.stringify(payload),
    });
    if (!response.ok) logLine("warn", "demo apns rejected", { status: response.status });
    return response.ok;
  } catch (error) {
    logLine("warn", "demo apns failed", { error: error instanceof Error ? error.name : "error" });
    return false;
  }
};
