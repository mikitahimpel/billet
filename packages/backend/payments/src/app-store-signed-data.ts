import { Effect, Result, Schema } from "effect";
import { Digest, KeyFormat, Signature } from "effect/crypto";
import { Base64, Base64Url } from "effect/encoding";
import { InvalidPurchase } from "./payments-error.ts";
import { type Certificate, ecdsaRawSignature, oids, parseCertificate, sameBytes } from "./x509.ts";

/** Checks as Apple's App Store Server Library does without OCSP; validity is judged at the
 * payload's `signedDate`. With `allowXcode`, a single-certificate JWS (Xcode's StoreKit testing)
 * is verified alone and reported as `xcode`, so the caller can insist on `Xcode`. */
export interface SignedDataOptions {
  readonly roots: ReadonlyArray<Uint8Array>;
  readonly allowXcode: boolean;
}

export interface VerifiedSignedData {
  readonly payload: unknown;
  readonly chain: "apple" | "xcode";
}

const Header = Schema.Struct({
  alg: Schema.Literal("ES256"),
  x5c: Schema.Array(Schema.String).check(Schema.isMinLength(1)),
});

const SignedDate = Schema.Struct({ signedDate: Schema.Number });

const reject = (reason: string): Effect.Effect<never, InvalidPurchase> =>
  Effect.fail(new InvalidPurchase({ reason }));

const fromResult = <A, E>(
  result: Result.Result<A, E>,
  reason: string,
): Effect.Effect<A, InvalidPurchase> =>
  Result.isSuccess(result) ? Effect.succeed(result.success) : reject(reason);

const decodeJson = (text: string, reason: string) =>
  Effect.try({
    try: (): unknown => JSON.parse(text),
    catch: () => new InvalidPurchase({ reason }),
  });

const parse = (der: Uint8Array) =>
  Effect.try({
    try: () => parseCertificate(der),
    catch: () => new InvalidPurchase({ reason: "certificate-malformed" }),
  });

const curves = {
  [oids.p256]: { algorithm: Signature.ecdsaP256, size: 32 },
  [oids.p384]: { algorithm: Signature.ecdsaP384, size: 48 },
} as const;

const hashes = {
  [oids.ecdsaWithSha256]: Digest.sha256,
  [oids.ecdsaWithSha384]: Digest.sha384,
} as const;

const curveOf = (certificate: Certificate) => {
  const curve =
    certificate.keyAlgorithm === oids.ecPublicKey && certificate.keyCurve !== undefined
      ? (curves as Record<string, (typeof curves)[keyof typeof curves]>)[certificate.keyCurve]
      : undefined;
  return curve === undefined ? reject("certificate-key-unsupported") : Effect.succeed(curve);
};

/** Is `child` signed by `parent`'s key, with a matching issuer name? */
const signedBy = Effect.fnUntraced(function* (child: Certificate, parent: Certificate) {
  if (!sameBytes(child.issuer, parent.subject)) return yield* reject("chain-name-mismatch");
  const hash = (hashes as Record<string, Digest.Algorithm>)[child.signatureAlgorithm];
  if (hash === undefined) return yield* reject("chain-algorithm-unsupported");
  const { algorithm, size } = yield* curveOf(parent);
  const key = yield* KeyFormat.decodePublic(
    KeyFormat.spki,
    { ...algorithm, hash },
    parent.publicKeyInfo,
  ).pipe(Effect.mapError(() => new InvalidPurchase({ reason: "certificate-key-invalid" })));
  const raw = yield* Effect.try({
    try: () => ecdsaRawSignature(child.signature, size),
    catch: () => new InvalidPurchase({ reason: "chain-signature-malformed" }),
  });
  const signature = yield* Signature.Signature;
  const valid = yield* signature
    .verify(key, raw, child.signed)
    .pipe(Effect.mapError(() => new InvalidPurchase({ reason: "chain-signature-invalid" })));
  if (!valid) return yield* reject("chain-signature-invalid");
});

const validAt = (certificate: Certificate, at: number) =>
  certificate.notBefore <= at && at <= certificate.notAfter;

/** The leaf's key, once the chain up to a trusted root holds. */
const checkAppleChain = Effect.fnUntraced(function* (
  ders: ReadonlyArray<Uint8Array>,
  roots: ReadonlyArray<Uint8Array>,
  at: number,
) {
  const [leafDer, intermediateDer, rootDer] = ders;
  if (ders.length !== 3 || leafDer === undefined || intermediateDer === undefined) {
    return yield* reject("chain-length");
  }
  if (rootDer === undefined || !roots.some((root) => sameBytes(root, rootDer))) {
    return yield* reject("chain-root-untrusted");
  }
  const [leaf, intermediate, root] = [
    yield* parse(leafDer),
    yield* parse(intermediateDer),
    yield* parse(rootDer),
  ];
  if (!intermediate.isCertificateAuthority) return yield* reject("chain-intermediate-not-ca");
  if (!leaf.extensions.includes(oids.appleAppStoreLeaf)) return yield* reject("chain-leaf-oid");
  if (!intermediate.extensions.includes(oids.appleWwdrIntermediate)) {
    return yield* reject("chain-intermediate-oid");
  }
  if (![leaf, intermediate, root].every((certificate) => validAt(certificate, at))) {
    return yield* reject("chain-expired");
  }
  yield* signedBy(intermediate, root);
  yield* signedBy(leaf, intermediate);
  return leaf;
});

export const verifySignedData = Effect.fnUntraced(function* (
  jws: string,
  options: SignedDataOptions,
): Effect.fn.Return<VerifiedSignedData, InvalidPurchase, Signature.Signature> {
  const parts = jws.split(".");
  const [headerPart, payloadPart, signaturePart] = parts;
  if (parts.length !== 3 || headerPart === undefined || payloadPart === undefined) {
    return yield* reject("jws-malformed");
  }
  const header = yield* fromResult(Base64Url.decodeString(headerPart), "jws-malformed").pipe(
    Effect.flatMap((text) => decodeJson(text, "jws-malformed")),
    Effect.flatMap((json) =>
      Schema.decodeUnknownEffect(Header)(json).pipe(
        Effect.mapError(() => new InvalidPurchase({ reason: "jws-header" })),
      ),
    ),
  );
  const payload = yield* fromResult(Base64Url.decodeString(payloadPart), "jws-malformed").pipe(
    Effect.flatMap((text) => decodeJson(text, "jws-malformed")),
  );
  const signature = yield* fromResult(Base64Url.decode(signaturePart ?? ""), "jws-malformed");
  const ders: Uint8Array[] = [];
  for (const entry of header.x5c)
    ders.push(yield* fromResult(Base64.decode(entry), "x5c-malformed"));

  const xcode = ders.length === 1;
  if (xcode && !options.allowXcode) return yield* reject("xcode-not-accepted");

  const leaf = xcode
    ? yield* parse(ders[0] ?? new Uint8Array())
    : yield* checkAppleChain(
        ders,
        options.roots,
        Schema.is(SignedDate)(payload) ? payload.signedDate : yield* reject("signed-date-missing"),
      );

  if (leaf.keyCurve !== oids.p256) return yield* reject("jws-key-not-p256");
  const key = yield* KeyFormat.decodePublic(
    KeyFormat.spki,
    Signature.ecdsaP256,
    leaf.publicKeyInfo,
  ).pipe(Effect.mapError(() => new InvalidPurchase({ reason: "certificate-key-invalid" })));
  const signer = yield* Signature.Signature;
  const valid = yield* signer
    .verify(key, signature, new TextEncoder().encode(`${headerPart}.${payloadPart}`))
    .pipe(Effect.mapError(() => new InvalidPurchase({ reason: "jws-signature-invalid" })));
  if (!valid) return yield* reject("jws-signature-invalid");

  return { payload, chain: xcode ? "xcode" : "apple" };
});

/** The trusted root for production: Apple Root CA - G3, from its base64 DER. */
export const decodeRoot = (base64: string): Uint8Array => {
  const result = Base64.decode(base64);
  if (Result.isFailure(result)) throw new Error("A root certificate constant is not base64.");
  return result.success;
};
