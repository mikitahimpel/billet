export const appleTeamId = "2666YPBJTB";

const encoder = new TextEncoder();

export const base64Url = (bytes: Uint8Array | string): string => {
  const raw = typeof bytes === "string" ? encoder.encode(bytes) : bytes;
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

/** Rejects if the PEM is not a P-256 key. */
export const signEs256 = async (
  key: { readonly pem: string; readonly keyId: string },
  claims: Readonly<Record<string, string | number>>,
): Promise<string> => {
  const header = base64Url(JSON.stringify({ alg: "ES256", kid: key.keyId }));
  const payload = base64Url(JSON.stringify(claims));
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    await importKey(key.pem),
    encoder.encode(`${header}.${payload}`),
  );
  return `${header}.${payload}.${base64Url(new Uint8Array(signature))}`;
};
