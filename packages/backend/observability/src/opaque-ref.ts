import { Effect, Option, type Tracer } from "effect";

const offset = 0xcbf29ce484222325n;
const prime = 0x100000001b3n;
const mask = 0xffffffffffffffffn;
const encoder = new TextEncoder();

/**
 * A stable, opaque stand-in for an id in logs and spans: 16 hex digits of FNV-1a 64. The same id
 * always gives the same ref, so one user's or pair's lines can be followed, but the ref is not
 * the id. To find a known id's lines, compute its ref (docs/observability.md).
 */
export const opaqueRef = (id: string): string => {
  let hash = offset;
  for (const byte of encoder.encode(id)) hash = ((hash ^ BigInt(byte)) * prime) & mask;
  return hash.toString(16).padStart(16, "0");
};

/** Who a request is about. Each id is turned into its ref before it is written anywhere. */
export interface RequestRefs {
  readonly user?: string | undefined;
  readonly pair?: string | undefined;
}

const rootOf = (span: Tracer.Span): Tracer.Span => {
  let current = span;
  for (;;) {
    const parent = Option.getOrUndefined(current.parent);
    if (parent?._tag !== "Span") return current;
    current = parent;
  }
};

/**
 * Puts `user.ref` and `pair.ref` on the current span and on its root (the request span), so a
 * request's `trace` line says whose request it was without naming them. Does nothing outside a
 * span.
 */
export const annotateRefs = (refs: RequestRefs): Effect.Effect<void> =>
  Effect.currentSpan.pipe(
    Effect.map((span) => {
      const attributes: Array<readonly [string, string]> = [];
      if (refs.user !== undefined) attributes.push(["user.ref", opaqueRef(refs.user)]);
      if (refs.pair !== undefined) attributes.push(["pair.ref", opaqueRef(refs.pair)]);
      const root = rootOf(span);
      for (const [key, value] of attributes) {
        span.attribute(key, value);
        if (root !== span) root.attribute(key, value);
      }
    }),
    Effect.ignore,
  );
