// Minimal APNs alert sender for the demo: one HTTP/2 request, no retries, no token cleanup.
export const APNS_TOPIC = "com.mikitahimpel.billet";
export const APNS_TEAM_ID = "2666YPBJTB";
const APNS_ORIGIN = "https://api.push.apple.com";

export interface ApnsCredentials {
  readonly key: string;
  readonly keyId: string;
}

export type ApnsFetch = (url: string, init: RequestInit) => Promise<Response>;

const base64Url = (bytes: Uint8Array | string): string => {
  const raw = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let binary = "";
  for (const byte of raw) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
};

const importKey = (pem: string): Promise<CryptoKey> => {
  const body = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, [
    "sign",
  ]);
};

const providerToken = async ({ key, keyId }: ApnsCredentials): Promise<string> => {
  const header = base64Url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = base64Url(
    JSON.stringify({ iss: APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) }),
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    await importKey(key),
    new TextEncoder().encode(`${header}.${claims}`),
  );
  return `${header}.${claims}.${base64Url(new Uint8Array(signature))}`;
};

/** Sends one "New note" alert. Resolves to whether APNs accepted it; never throws, never logs the token. */
export const sendNoteAlert = async (
  credentials: ApnsCredentials,
  deviceToken: string,
  noteURL: string,
  send: ApnsFetch = fetch,
): Promise<boolean> => {
  try {
    const response = await send(`${APNS_ORIGIN}/3/device/${deviceToken}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${await providerToken(credentials)}`,
        "apns-topic": APNS_TOPIC,
        "apns-push-type": "alert",
        "apns-priority": "10",
      },
      body: JSON.stringify({
        aps: { alert: { body: "New note" }, "mutable-content": 1 },
        noteURL,
      }),
    });
    if (!response.ok) console.warn(`demo apns rejected: status ${response.status}`);
    return response.ok;
  } catch (error) {
    console.warn(`demo apns failed: ${error instanceof Error ? error.name : "error"}`);
    return false;
  }
};
