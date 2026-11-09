/** Just enough DER and X.509 to check an App Store chain in a Worker, where Node's
 * `X509Certificate` does not exist. Every malformed input throws `MalformedCertificate`. */

export class MalformedCertificate extends Error {
  override readonly name = "MalformedCertificate";
}

interface Node {
  readonly tag: number;
  /** The whole element: tag, length and content. */
  readonly element: Uint8Array;
  readonly content: Uint8Array;
}

const tags = {
  boolean: 0x01,
  integer: 0x02,
  bitString: 0x03,
  octetString: 0x04,
  oid: 0x06,
  utcTime: 0x17,
  generalizedTime: 0x18,
  sequence: 0x30,
  explicit0: 0xa0,
  explicit3: 0xa3,
} as const;

const malformed = (what: string): never => {
  throw new MalformedCertificate(what);
};

/** The element at `offset`. Only definite lengths, as DER requires. */
const readNode = (bytes: Uint8Array, offset: number): Node => {
  const tag = bytes[offset] ?? malformed("truncated tag");
  // Multi-byte tags never occur in a certificate.
  if ((tag & 0x1f) === 0x1f) malformed("long tag");
  const first = bytes[offset + 1] ?? malformed("truncated length");
  let length = first;
  let header = 2;
  if (first & 0x80) {
    const count = first & 0x7f;
    if (count === 0 || count > 4) malformed("length form");
    length = 0;
    for (let i = 0; i < count; i++) {
      length = length * 256 + (bytes[offset + 2 + i] ?? malformed("truncated length"));
    }
    header += count;
  }
  const end = offset + header + length;
  if (end > bytes.length) malformed("truncated content");
  return {
    tag,
    element: bytes.subarray(offset, end),
    content: bytes.subarray(offset + header, end),
  };
};

const childrenOf = (node: Node): ReadonlyArray<Node> => {
  const children: Node[] = [];
  let offset = 0;
  while (offset < node.content.length) {
    const child = readNode(node.content, offset);
    children.push(child);
    offset += child.element.length;
  }
  return children;
};

const expect = (node: Node | undefined, tag: number, what: string): Node =>
  node !== undefined && node.tag === tag ? node : malformed(what);

const only = (bytes: Uint8Array, tag: number, what: string): Node => {
  const node = expect(readNode(bytes, 0), tag, what);
  if (node.element.length !== bytes.length) malformed(`${what}: trailing bytes`);
  return node;
};

const oidOf = (node: Node): string => {
  const { content } = expect(node, tags.oid, "object identifier");
  const first = content[0] ?? malformed("empty object identifier");
  const parts = [Math.floor(first / 40), first % 40];
  let value = 0;
  for (const byte of content.subarray(1)) {
    value = value * 128 + (byte & 0x7f);
    if ((byte & 0x80) === 0) {
      parts.push(value);
      value = 0;
    }
  }
  return parts.join(".");
};

const timeOf = (node: Node): number => {
  const text = new TextDecoder().decode(node.content);
  const match =
    node.tag === tags.utcTime
      ? /^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(text)
      : node.tag === tags.generalizedTime
        ? /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(text)
        : null;
  if (match === null) return malformed("time");
  const [, y = "", mo = "", d = "", h = "", mi = "", s = ""] = match;
  // RFC 5280: a two-digit year from 50 is 19xx, below it 20xx.
  const year = y.length === 2 ? (Number(y) >= 50 ? 1900 : 2000) + Number(y) : Number(y);
  return Date.UTC(year, Number(mo) - 1, Number(d), Number(h), Number(mi), Number(s));
};

/** A BIT STRING's bytes, which in a certificate always have no unused bits. */
const bitsOf = (node: Node): Uint8Array => {
  const { content } = expect(node, tags.bitString, "bit string");
  if (content[0] !== 0) malformed("unused bits");
  return content.subarray(1);
};

export const oids = {
  ecPublicKey: "1.2.840.10045.2.1",
  p256: "1.2.840.10045.3.1.7",
  p384: "1.3.132.0.34",
  ecdsaWithSha256: "1.2.840.10045.4.3.2",
  ecdsaWithSha384: "1.2.840.10045.4.3.3",
  basicConstraints: "2.5.29.19",
  /** Apple's marker on the App Store's signing (leaf) certificate. */
  appleAppStoreLeaf: "1.2.840.113635.100.6.11.1",
  /** Apple's marker on the Worldwide Developer Relations intermediate. */
  appleWwdrIntermediate: "1.2.840.113635.100.6.2.1",
} as const;

export interface Certificate {
  /** The DER of the whole certificate. */
  readonly der: Uint8Array;
  /** The bytes the issuer signed. */
  readonly signed: Uint8Array;
  readonly signatureAlgorithm: string;
  /** The issuer's signature, DER-encoded as ASN.1 for ECDSA. */
  readonly signature: Uint8Array;
  /** The issuer and subject names, DER, compared byte for byte. */
  readonly issuer: Uint8Array;
  readonly subject: Uint8Array;
  readonly notBefore: number;
  readonly notAfter: number;
  /** The public key, as DER SubjectPublicKeyInfo. */
  readonly publicKeyInfo: Uint8Array;
  /** The key's algorithm and, for EC keys, its curve. */
  readonly keyAlgorithm: string;
  readonly keyCurve: string | undefined;
  readonly extensions: ReadonlyArray<string>;
  readonly isCertificateAuthority: boolean;
}

const basicConstraintsCa = (value: Uint8Array): boolean => {
  const [first] = childrenOf(only(value, tags.sequence, "basic constraints"));
  return first?.tag === tags.boolean && first.content[0] !== 0;
};

export const parseCertificate = (der: Uint8Array): Certificate => {
  const [tbs, algorithm, signature] = childrenOf(only(der, tags.sequence, "certificate"));
  const tbsNode = expect(tbs, tags.sequence, "to-be-signed");
  const [signatureAlgorithmOid] = childrenOf(expect(algorithm, tags.sequence, "algorithm"));

  const fields = [...childrenOf(tbsNode)];
  if (fields[0]?.tag === tags.explicit0) fields.shift();
  const [, , issuer, validity, subject, keyInfo, ...rest] = fields;
  const [notBefore, notAfter] = childrenOf(expect(validity, tags.sequence, "validity"));
  const keyInfoNode = expect(keyInfo, tags.sequence, "public key info");
  const [keyAlgorithm] = childrenOf(keyInfoNode);
  const [keyAlgorithmOid, keyParameters] = childrenOf(
    expect(keyAlgorithm, tags.sequence, "key algorithm"),
  );

  const extensions: string[] = [];
  let isCertificateAuthority = false;
  const extensionsNode = rest.find((node) => node.tag === tags.explicit3);
  if (extensionsNode !== undefined) {
    const [list] = childrenOf(extensionsNode);
    for (const extension of childrenOf(expect(list, tags.sequence, "extensions"))) {
      const parts = childrenOf(expect(extension, tags.sequence, "extension"));
      const id = oidOf(parts[0] ?? malformed("extension id"));
      extensions.push(id);
      if (id === oids.basicConstraints) {
        const value = expect(parts.at(-1), tags.octetString, "extension value");
        isCertificateAuthority = basicConstraintsCa(value.content);
      }
    }
  }

  return {
    der,
    signed: tbsNode.element,
    signatureAlgorithm: oidOf(signatureAlgorithmOid ?? malformed("signature algorithm")),
    signature: bitsOf(signature ?? malformed("signature")),
    issuer: expect(issuer, tags.sequence, "issuer").element,
    subject: expect(subject, tags.sequence, "subject").element,
    notBefore: timeOf(notBefore ?? malformed("not before")),
    notAfter: timeOf(notAfter ?? malformed("not after")),
    publicKeyInfo: keyInfoNode.element,
    keyAlgorithm: oidOf(keyAlgorithmOid ?? malformed("key algorithm")),
    keyCurve: keyParameters?.tag === tags.oid ? oidOf(keyParameters) : undefined,
    extensions,
    isCertificateAuthority,
  };
};

const unsigned = (node: Node | undefined, size: number): Uint8Array => {
  const { content } = expect(node, tags.integer, "signature integer");
  let start = 0;
  while (start < content.length - 1 && content[start] === 0) start++;
  const digits = content.subarray(start);
  if (digits.length > size) malformed("signature integer size");
  const out = new Uint8Array(size);
  out.set(digits, size - digits.length);
  return out;
};

/** DER `SEQUENCE { r, s }` to the fixed-size `r‖s` that Web Crypto verifies. `size` is the
 * curve's byte length: 32 for P-256, 48 for P-384. */
export const ecdsaRawSignature = (der: Uint8Array, size: number): Uint8Array => {
  const [r, s, extra] = childrenOf(only(der, tags.sequence, "ecdsa signature"));
  if (extra !== undefined) malformed("ecdsa signature fields");
  const raw = new Uint8Array(size * 2);
  raw.set(unsigned(r, size), 0);
  raw.set(unsigned(s, size), size);
  return raw;
};

export const sameBytes = (a: Uint8Array, b: Uint8Array): boolean =>
  a.length === b.length && a.every((byte, i) => byte === b[i]);
