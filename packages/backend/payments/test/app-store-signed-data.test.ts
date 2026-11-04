import { Effect, Layer } from "effect";
import { Digest, SecureRandom, Signature } from "effect/crypto";
import { Base64 } from "effect/encoding";
import { describe, expect, it } from "vitest";
import { appleRootCaG3 } from "../src/apple-root-certificates.ts";
import { decodeRoot, verifySignedData } from "../src/app-store-signed-data.ts";
import { oids, parseCertificate } from "../src/x509.ts";
import { makeChain, makeXcodeChain, signJws, transactionPayload } from "./app-store-signer.ts";

const cryptoLayer = Layer.mergeAll(
  Signature.layerWebCrypto.pipe(Layer.provide(SecureRandom.layerWebCrypto)),
  Digest.layerWebCrypto,
);

const verify = (jws: string, roots: ReadonlyArray<Uint8Array>, allowXcode = false) =>
  Effect.runPromise(
    verifySignedData(jws, { roots, allowXcode }).pipe(
      Effect.map(({ chain }) => ({ ok: chain })),
      Effect.catchTag("InvalidPurchase", ({ reason }) => Effect.succeed({ refused: reason })),
      Effect.provide(cryptoLayer),
    ),
  );

const hex = (bytes: Uint8Array) =>
  [...bytes].map((byte) => byte.toString(16).padStart(2, "0").toUpperCase()).join(":");

describe("Apple Root CA - G3", () => {
  it("is the certificate Apple publishes", async () => {
    const der = decodeRoot(appleRootCaG3);
    const fingerprint = new Uint8Array(await crypto.subtle.digest("SHA-256", der));
    expect(hex(fingerprint)).toBe(
      "63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79",
    );
    const root = parseCertificate(der);
    expect(root.keyCurve).toBe(oids.p384);
    expect(root.isCertificateAuthority).toBe(true);
    expect(new Date(root.notAfter).toISOString()).toBe("2039-04-30T18:19:06.000Z");
  });
});

describe("verifying App Store signed data", () => {
  it("accepts a JWS signed down an Apple-shaped chain to a trusted root", async () => {
    const { root, chain, leafKey } = await makeChain();
    const jws = await signJws(transactionPayload(), chain, leafKey);
    expect(await verify(jws, [root])).toEqual({ ok: "apple" });
  });

  it("refuses a tampered payload", async () => {
    const { root, chain, leafKey } = await makeChain();
    const [header, , signature] = (await signJws(transactionPayload(), chain, leafKey)).split(".");
    const forged = (await signJws(transactionPayload({ productId: "x" }), chain, leafKey)).split(
      ".",
    )[1];
    expect(await verify(`${header}.${forged}.${signature}`, [root])).toEqual({
      refused: "jws-signature-invalid",
    });
  });

  it("refuses a chain that ends in another root", async () => {
    const trusted = await makeChain();
    const other = await makeChain();
    const jws = await signJws(transactionPayload(), other.chain, other.leafKey);
    expect(await verify(jws, [trusted.root])).toEqual({ refused: "chain-root-untrusted" });
    expect(await verify(jws, [decodeRoot(appleRootCaG3)])).toEqual({
      refused: "chain-root-untrusted",
    });
  });

  it("refuses a leaf the intermediate did not sign", async () => {
    const { root, chain, leafKey } = await makeChain({ leafSignedByStranger: true });
    const jws = await signJws(transactionPayload(), chain, leafKey);
    expect(await verify(jws, [root])).toEqual({ refused: "chain-signature-invalid" });
  });

  it("refuses a JWS signed by a key that is not the leaf's", async () => {
    const { root, chain } = await makeChain();
    const { leafKey: other } = await makeChain();
    const jws = await signJws(transactionPayload(), chain, other);
    expect(await verify(jws, [root])).toEqual({ refused: "jws-signature-invalid" });
  });

  it.each([
    ["the leaf's Apple marker", { leafMarker: false }, "chain-leaf-oid"],
    ["the intermediate's Apple marker", { intermediateMarker: false }, "chain-intermediate-oid"],
    ["a CA intermediate", { intermediateIsCa: false }, "chain-intermediate-not-ca"],
  ])("refuses a chain without %s", async (_, options, reason) => {
    const { root, chain, leafKey } = await makeChain(options);
    const jws = await signJws(transactionPayload(), chain, leafKey);
    expect(await verify(jws, [root])).toEqual({ refused: reason });
  });

  it("refuses a leaf that had expired when the data was signed", async () => {
    const { root, chain, leafKey } = await makeChain({ leafNotAfter: Date.UTC(2026, 0, 1) });
    const jws = await signJws(transactionPayload(), chain, leafKey);
    expect(await verify(jws, [root])).toEqual({ refused: "chain-expired" });
  });

  it("refuses a chain of two", async () => {
    const { root, chain, leafKey } = await makeChain();
    const jws = await signJws(transactionPayload(), chain.slice(0, 2), leafKey);
    expect(await verify(jws, [root])).toEqual({ refused: "chain-length" });
  });

  it("accepts Xcode's self-signed certificate only when allowed", async () => {
    const { root } = await makeChain();
    const xcode = await makeXcodeChain();
    const jws = await signJws(
      transactionPayload({ environment: "Xcode" }),
      xcode.chain,
      xcode.leafKey,
    );
    expect(await verify(jws, [root], true)).toEqual({ ok: "xcode" });
    expect(await verify(jws, [root], false)).toEqual({ refused: "xcode-not-accepted" });
  });

  it.each([
    ["not a JWS", "abc"],
    ["a header that is not JSON", "e30x.e30.AA"],
    ["no chain", `${btoa('{"alg":"ES256"}')}.e30.AA`],
    ["another algorithm", `${btoa(JSON.stringify({ alg: "HS256", x5c: ["AA"] }))}.e30.AA`],
    [
      "a certificate that is not DER",
      `${btoa(JSON.stringify({ alg: "ES256", x5c: [Base64.encode("x"), "AA", "AA"] }))}.${btoa(JSON.stringify({ signedDate: 1 }))}.AA`,
    ],
  ])("refuses %s", async (_, jws) => {
    const { root } = await makeChain();
    expect(await verify(jws.replaceAll("=", ""), [root])).toHaveProperty("refused");
  });
});
