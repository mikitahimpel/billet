import { Base64, Base64Url } from "effect/encoding";
import { oids } from "../src/x509.ts";

// Builds certificate chains shaped like Apple's (a P-384 root and intermediate, a P-256 leaf, the
// same marker extensions) and signs JWS with them, so tests can check the verifier with keys they
// own. None of this ever signs anything real.

const concat = (...parts: ReadonlyArray<Uint8Array | ReadonlyArray<number>>): Uint8Array => {
  const out = new Uint8Array(parts.reduce((sum, part) => sum + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
};

const lengthOf = (n: number): ReadonlyArray<number> =>
  n < 0x80 ? [n] : n < 0x100 ? [0x81, n] : [0x82, n >> 8, n & 0xff];

const tlv = (tag: number, ...parts: ReadonlyArray<Uint8Array>) => {
  const content = concat(...parts);
  return concat([tag, ...lengthOf(content.length)], content);
};

const sequence = (...parts: ReadonlyArray<Uint8Array>) => tlv(0x30, ...parts);

const integer = (bytes: Uint8Array) => {
  let start = 0;
  while (start < bytes.length - 1 && bytes[start] === 0) start++;
  const digits = bytes.subarray(start);
  return tlv(0x02, (digits[0] ?? 0) & 0x80 ? concat([0], digits) : digits);
};

const objectId = (dotted: string) => {
  const [a = 0, b = 0, ...rest] = dotted.split(".").map(Number);
  const bytes = [a * 40 + b];
  for (const part of rest) {
    const groups = [part & 0x7f];
    for (let value = part >> 7; value > 0; value >>= 7) groups.unshift((value & 0x7f) | 0x80);
    bytes.push(...groups);
  }
  return tlv(0x06, Uint8Array.from(bytes));
};

const text = (value: string) => new TextEncoder().encode(value);

const time = (millis: number) => {
  const iso = new Date(millis).toISOString().replace(/[-:T]/g, "").slice(0, 14);
  return Number(iso.slice(0, 4)) < 2050
    ? tlv(0x17, text(`${iso.slice(2)}Z`))
    : tlv(0x18, text(`${iso}Z`));
};

const name = (commonName: string) =>
  sequence(tlv(0x31, sequence(objectId("2.5.4.3"), tlv(0x0c, text(commonName)))));

const extension = (id: string, value: Uint8Array, critical = false) =>
  sequence(objectId(id), ...(critical ? [tlv(0x01, Uint8Array.of(0xff))] : []), tlv(0x04, value));

const caConstraint = (isCa: boolean) =>
  extension(
    oids.basicConstraints,
    sequence(...(isCa ? [tlv(0x01, Uint8Array.of(0xff))] : [])),
    true,
  );

const marker = (id: string) => extension(id, tlv(0x05));

const curves = {
  "P-256": { hash: "SHA-256", size: 32, signatureOid: oids.ecdsaWithSha256 },
  "P-384": { hash: "SHA-384", size: 48, signatureOid: oids.ecdsaWithSha384 },
} as const;
type Curve = keyof typeof curves;

export interface TestKey {
  readonly curve: Curve;
  readonly keys: CryptoKeyPair;
}

export const generateKey = async (curve: Curve): Promise<TestKey> => ({
  curve,
  keys: (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: curve }, true, [
    "sign",
    "verify",
  ])) as CryptoKeyPair,
});

const signRaw = async (key: TestKey, data: Uint8Array) =>
  new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: curves[key.curve].hash },
      key.keys.privateKey,
      data,
    ),
  );

export interface CertificateOptions {
  readonly subject: string;
  readonly issuer: string;
  readonly key: TestKey;
  readonly issuerKey: TestKey;
  readonly extensions?: ReadonlyArray<Uint8Array>;
  readonly notBefore?: number;
  readonly notAfter?: number;
}

export const certificate = async (options: CertificateOptions): Promise<Uint8Array> => {
  const { signatureOid, size } = curves[options.issuerKey.curve];
  const publicKeyInfo = new Uint8Array(
    (await crypto.subtle.exportKey("spki", options.key.keys.publicKey)) as ArrayBuffer,
  );
  const tbs = sequence(
    tlv(0xa0, integer(Uint8Array.of(2))),
    integer(crypto.getRandomValues(new Uint8Array(8))),
    sequence(objectId(signatureOid)),
    name(options.issuer),
    sequence(
      time(options.notBefore ?? Date.UTC(2020, 0, 1)),
      time(options.notAfter ?? Date.UTC(2040, 0, 1)),
    ),
    name(options.subject),
    publicKeyInfo,
    ...(options.extensions === undefined || options.extensions.length === 0
      ? []
      : [tlv(0xa3, sequence(...options.extensions))]),
  );
  const raw = await signRaw(options.issuerKey, tbs);
  const signature = sequence(integer(raw.subarray(0, size)), integer(raw.subarray(size)));
  return sequence(tbs, sequence(objectId(signatureOid)), tlv(0x03, concat([0], signature)));
};

export interface ChainOptions {
  readonly leafMarker?: boolean;
  readonly intermediateMarker?: boolean;
  readonly intermediateIsCa?: boolean;
  readonly leafNotAfter?: number;
  /** Sign the leaf with a key other than the intermediate's. */
  readonly leafSignedByStranger?: boolean;
}

export interface TestChain {
  readonly root: Uint8Array;
  readonly chain: ReadonlyArray<Uint8Array>;
  readonly leafKey: TestKey;
}

/** A root, an intermediate and a leaf, by default exactly as Apple's are shaped. */
export const makeChain = async (options: ChainOptions = {}): Promise<TestChain> => {
  const [rootKey, intermediateKey, leafKey, strangerKey] = await Promise.all([
    generateKey("P-384"),
    generateKey("P-384"),
    generateKey("P-256"),
    generateKey("P-384"),
  ]);
  const root = await certificate({
    subject: "Test Root CA",
    issuer: "Test Root CA",
    key: rootKey,
    issuerKey: rootKey,
    extensions: [caConstraint(true)],
  });
  const intermediate = await certificate({
    subject: "Test WWDR CA",
    issuer: "Test Root CA",
    key: intermediateKey,
    issuerKey: rootKey,
    extensions: [
      caConstraint(options.intermediateIsCa ?? true),
      ...(options.intermediateMarker === false ? [] : [marker(oids.appleWwdrIntermediate)]),
    ],
  });
  const leaf = await certificate({
    subject: "Test App Store Signing",
    issuer: "Test WWDR CA",
    key: leafKey,
    issuerKey: options.leafSignedByStranger === true ? strangerKey : intermediateKey,
    extensions: options.leafMarker === false ? [] : [marker(oids.appleAppStoreLeaf)],
    ...(options.leafNotAfter === undefined ? {} : { notAfter: options.leafNotAfter }),
  });
  return { root, chain: [leaf, intermediate, root], leafKey };
};

/** One self-signed P-256 certificate, as Xcode's StoreKit testing signs with. */
export const makeXcodeChain = async (): Promise<TestChain> => {
  const key = await generateKey("P-256");
  const self = await certificate({
    subject: "StoreKit Testing in Xcode",
    issuer: "StoreKit Testing in Xcode",
    key,
    issuerKey: key,
  });
  return { root: self, chain: [self], leafKey: key };
};

/** A compact JWS over `payload`, with `chain` in `x5c`, signed by `key`. */
export const signJws = async (
  payload: unknown,
  chain: ReadonlyArray<Uint8Array>,
  key: TestKey,
): Promise<string> => {
  const header = Base64Url.encode(
    JSON.stringify({ alg: "ES256", x5c: chain.map((der) => Base64.encode(der)) }),
  );
  const body = Base64Url.encode(JSON.stringify(payload));
  const signature = await signRaw(key, text(`${header}.${body}`));
  return `${header}.${body}.${Base64Url.encode(signature)}`;
};

export const bundleId = "com.mikitahimpel.billet";

/** A StoreKit 2 transaction for a consumable pack, as Apple signs it, with `overrides` applied. */
export const transactionPayload = (overrides: Record<string, unknown> = {}) => ({
  transactionId: "2000000900000001",
  originalTransactionId: "2000000900000001",
  bundleId,
  productId: "com.mikitahimpel.billet.stamps.100",
  purchaseDate: Date.UTC(2026, 10, 4, 15),
  originalPurchaseDate: Date.UTC(2026, 10, 4, 15),
  quantity: 1,
  type: "Consumable",
  inAppOwnershipType: "PURCHASED",
  signedDate: Date.UTC(2026, 10, 4, 15),
  environment: "Sandbox",
  transactionReason: "PURCHASE",
  storefront: "USA",
  price: 990,
  currency: "USD",
  ...overrides,
});

/** An App Store Server Notification V2 payload around a signed transaction. */
export const notificationPayload = (
  notificationType: string,
  signedTransactionInfo: string | undefined,
  overrides: Record<string, unknown> = {},
) => ({
  notificationType,
  notificationUUID: crypto.randomUUID(),
  data: {
    bundleId,
    environment: "Sandbox",
    ...(signedTransactionInfo === undefined ? {} : { signedTransactionInfo }),
  },
  version: "2.0",
  signedDate: Date.UTC(2026, 10, 5, 9),
  ...overrides,
});
