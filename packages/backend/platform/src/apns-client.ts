// The APNs client for the PairRoom's push lanes: alert, WidgetKit and Live Activity pushes, with a
// cached provider token and each failure classified into what the ledger should do about it.
import { appleTeamId, signEs256 } from "./es256-jwt.ts";

/** The app's bundle id: the alert topic, and the root of the other two. */
export const appBundleId = "com.mikitahimpel.billet";

export type ApnsPushType = "alert" | "widgets" | "liveactivity";
export type ApnsEnvironment = "sandbox" | "production";

const hosts: Record<ApnsEnvironment, string> = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
};

/** APNs routes each push type to its own topic: the bundle id, or the bundle id with a suffix. */
export const topicOf = (pushType: ApnsPushType): string => {
  switch (pushType) {
    case "alert":
      return appBundleId;
    case "widgets":
      return `${appBundleId}.push-type.widgets`;
    case "liveactivity":
      return `${appBundleId}.push-type.liveactivity`;
  }
};

export interface ApnsPush {
  readonly token: string;
  readonly environment: ApnsEnvironment;
  readonly pushType: ApnsPushType;
  /** The whole APNs JSON body, `aps` included. */
  readonly body: unknown;
  /** Pushes with the same id replace each other on the phone. */
  readonly collapseId?: string;
}

/**
 * What one push came to.
 * - `Delivered`: APNs accepted it.
 * - `Unregistered`: the token is dead; drop it and never send to it again.
 * - `Retry`: worth trying again later (throttled, APNs down, the network, an expired provider token).
 * - `Rejected`: this push will never be accepted (a malformed body, a wrong topic); do not retry.
 */
export type ApnsResult =
  | { readonly _tag: "Delivered" }
  | { readonly _tag: "Unregistered"; readonly reason: string }
  | { readonly _tag: "Retry"; readonly reason: string }
  | { readonly _tag: "Rejected"; readonly reason: string };

/** Turns an APNs answer into an `ApnsResult`, from its status and the `reason` in its body. */
export const classify = (status: number, reason: string): ApnsResult => {
  if (status === 200) return { _tag: "Delivered" };
  if (status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") {
    return { _tag: "Unregistered", reason: reason || String(status) };
  }
  // A token for the other environment is a wrong registration, not a dead device; it is dropped
  // the same way, and the phone registers the right one on its next launch.
  if (reason === "BadEnvironmentKeyInToken" || reason === "DeviceTokenNotForTopic") {
    return { _tag: "Unregistered", reason };
  }
  if (status === 403 && (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken")) {
    return { _tag: "Retry", reason };
  }
  if (status === 429 || status >= 500) return { _tag: "Retry", reason: reason || String(status) };
  return { _tag: "Rejected", reason: reason || String(status) };
};

export interface ApnsCredentials {
  /** The `.p8` key, PKCS #8 PEM. */
  readonly key: string;
  readonly keyId: string;
}

/** APNs asks for a new provider token at most every 20 minutes and refuses one older than 60. */
export const providerTokenLifetimeSeconds = 50 * 60;

/** Signs the provider token once and reuses it until it is due for renewal. */
export class ProviderTokens {
  private cached:
    | { readonly keyId: string; readonly token: string; readonly issuedAt: number }
    | undefined;

  constructor(private readonly nowSeconds: () => number) {}

  async token(credentials: ApnsCredentials): Promise<string> {
    const now = this.nowSeconds();
    const cached = this.cached;
    if (
      cached !== undefined &&
      cached.keyId === credentials.keyId &&
      now - cached.issuedAt < providerTokenLifetimeSeconds
    ) {
      return cached.token;
    }
    const token = await signEs256(
      { pem: credentials.key, keyId: credentials.keyId },
      { iss: appleTeamId, iat: now },
    );
    this.cached = { keyId: credentials.keyId, token, issuedAt: now };
    return token;
  }

  /** Forgets the cached token, after APNs said it is expired or invalid. */
  reset(): void {
    this.cached = undefined;
  }
}

export type ApnsFetch = (url: string, init: RequestInit) => Promise<Response>;

/** The headers APNs needs for a push type. Start and end of a Live Activity go at once (10). */
const headersOf = (push: ApnsPush, providerToken: string): Record<string, string> => ({
  authorization: `bearer ${providerToken}`,
  "apns-push-type": push.pushType,
  "apns-topic": topicOf(push.pushType),
  // WidgetKit pushes are budgeted by the system either way; 5 lets APNs batch them with others.
  "apns-priority": push.pushType === "widgets" ? "5" : "10",
  "content-type": "application/json",
  ...(push.collapseId === undefined ? {} : { "apns-collapse-id": push.collapseId }),
});

/** Sends one push. Never throws: a network failure is a `Retry`. */
export const sendApns = async (
  push: ApnsPush,
  credentials: ApnsCredentials,
  tokens: ProviderTokens,
  fetcher: ApnsFetch = fetch,
): Promise<ApnsResult> => {
  let response: Response;
  try {
    const providerToken = await tokens.token(credentials);
    response = await fetcher(`${hosts[push.environment]}/3/device/${push.token}`, {
      method: "POST",
      headers: headersOf(push, providerToken),
      body: JSON.stringify(push.body),
    });
  } catch (error) {
    return { _tag: "Retry", reason: error instanceof Error ? error.message : "network" };
  }
  let reason = "";
  if (response.status !== 200) {
    try {
      const body: unknown = await response.json();
      if (typeof body === "object" && body !== null && "reason" in body)
        reason = String(body.reason);
    } catch {
      // No JSON body: the status alone decides.
    }
  }
  const result = classify(response.status, reason);
  if (result._tag === "Retry" && response.status === 403) tokens.reset();
  return result;
};
