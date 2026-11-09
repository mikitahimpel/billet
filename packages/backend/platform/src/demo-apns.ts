import { appBundleId, legacyBundleId } from "./apns-client.ts";
import { appleTeamId, signEs256 } from "./es256-jwt.ts";
import { logLine } from "./demo-trace.ts";
import { type Now, systemNow } from "./wall-clock.ts";

// One HTTP/2 request, no retries, no token cleanup.
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

const notForTopic = async (response: Response): Promise<boolean> => {
  if (response.status !== 400) return false;
  try {
    const body: unknown = await response.json();
    return typeof body === "object" && body !== null && "reason" in body
      ? body.reason === "DeviceTokenNotForTopic"
      : false;
  } catch {
    return false;
  }
};

/** Never throws. A token from the first app's builds is sent again under its bundle id. */
export const sendAlert = async (
  credentials: ApnsCredentials,
  deviceToken: string,
  payload: Readonly<Record<string, unknown>>,
  send: ApnsFetch = fetch,
  now: Now = systemNow,
): Promise<boolean> => {
  try {
    const authorization = `bearer ${await providerToken(credentials, now)}`;
    const post = (topic: string) =>
      send(`${APNS_ORIGIN}/3/device/${deviceToken}`, {
        method: "POST",
        headers: {
          authorization,
          "apns-topic": topic,
          "apns-push-type": "alert",
          "apns-priority": "10",
        },
        body: JSON.stringify(payload),
      });
    let response = await post(appBundleId);
    if (await notForTopic(response)) response = await post(legacyBundleId);
    if (!response.ok) logLine("warn", "demo apns rejected", { status: response.status });
    return response.ok;
  } catch (error) {
    logLine("warn", "demo apns failed", { error: error instanceof Error ? error.name : "error" });
    return false;
  }
};
