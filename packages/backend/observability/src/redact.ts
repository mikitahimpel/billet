import { type Cause, Redacted } from "effect";

/** What a log line shows in place of anything secret or personal. */
export const hidden = "<redacted>";

/** Matched anywhere in the name, so `sessionToken`, `mediaKey` and `noteText` are all hidden. */
const sensitiveKey =
  /token|secret|password|passphrase|authori[sz]ation|cookie|session|email|e-mail|phone|body|text|content|key|signature|credential|stroke/i;

const emailShaped = /[^\s@]+@[^\s@]+\.[^\s@]+/;
/** A bearer value, a JWT, a key: one long run of token characters. */
const tokenShaped = /^(?:bearer\s+)?[\w.~+/=-]{32,}$/i;

const maxDepth = 4;
const maxEntries = 30;
const maxString = 200;
const maxFrames = 6;

const redactString = (value: string): string => {
  if (emailShaped.test(value) || tokenShaped.test(value)) return hidden;
  return value.length > maxString ? `${value.slice(0, maxString)}…` : value;
};

/** The frames of a stack without its first line, which holds the error's message. */
const framesOf = (stack: string | undefined): ReadonlyArray<string> | undefined => {
  if (stack === undefined) return undefined;
  const frames = stack
    .split("\n")
    .slice(1)
    .map((frame) => frame.trim())
    .filter((frame) => frame.startsWith("at "));
  return frames.length === 0 ? undefined : frames.slice(0, maxFrames);
};

/** Never the message: it can quote the input. Tagged errors' fields are fixed labels. */
const redactError = (error: Error, depth: number): Record<string, unknown> => {
  const out: Record<string, unknown> = { name: error.name };
  for (const [key, field] of Object.entries(error).slice(0, maxEntries)) {
    if (key === "message" || key === "stack") continue;
    out[key] = sensitiveKey.test(key) ? hidden : redact(field, depth + 1);
  }
  const frames = framesOf(error.stack);
  if (frames !== undefined) out["stack"] = frames;
  if (error.cause !== undefined && !("cause" in out)) out["cause"] = redact(error.cause, depth + 1);
  return out;
};

/** Hides secrets, emails and sensitive fields, drops error messages, cuts deep or long values. */
export const redact = (value: unknown, depth = 0): unknown => {
  if (Redacted.isRedacted(value)) return hidden;
  switch (typeof value) {
    case "string":
      return redactString(value);
    case "number":
    case "boolean":
    case "undefined":
      return value;
    case "bigint":
      return value.toString();
    case "function":
    case "symbol":
      return `<${typeof value}>`;
  }
  if (value === null || typeof value !== "object") return null;
  if (depth >= maxDepth) return "…";
  if (value instanceof Error) return redactError(value, depth);
  if (value instanceof Date) return value.toISOString();
  if (value instanceof ArrayBuffer || ArrayBuffer.isView(value)) {
    return `<${value.byteLength} bytes>`;
  }
  if (Array.isArray(value))
    return value.slice(0, maxEntries).map((item) => redact(item, depth + 1));
  if (value instanceof Map) return redact(Object.fromEntries(value), depth);
  if (value instanceof Set) return redact([...value], depth);
  const out: Record<string, unknown> = {};
  for (const [key, field] of Object.entries(value).slice(0, maxEntries)) {
    out[key] = sensitiveKey.test(key) ? hidden : redact(field, depth + 1);
  }
  return out;
};

/** Redacts one named value, hiding it outright when the name is sensitive. */
export const redactField = (key: string, value: unknown): unknown =>
  sensitiveKey.test(key) ? hidden : redact(value);

/** A cause as a short list: each failure's redacted error, each defect's class and stack. */
export const summarizeCause = (cause: Cause.Cause<unknown>): ReadonlyArray<unknown> =>
  cause.reasons.slice(0, 5).map((reason) => {
    switch (reason._tag) {
      case "Fail":
        return { kind: "fail", error: redact(reason.error) };
      case "Die":
        return { kind: "defect", error: redact(reason.defect) };
      case "Interrupt":
        return { kind: "interrupt" };
    }
  });

/** The tag or class of a cause's first failure, for a one-word status: `AuthUnavailable`. */
export const causeLabel = (cause: Cause.Cause<unknown>): string => {
  const reason = cause.reasons[0];
  if (reason === undefined) return "unknown";
  if (reason._tag === "Interrupt") return "interrupted";
  const error = reason._tag === "Fail" ? reason.error : reason.defect;
  if (typeof error === "object" && error !== null) {
    if ("_tag" in error && typeof error._tag === "string") return error._tag;
    if (error instanceof Error) return error.name;
  }
  return reason._tag === "Fail" ? "failure" : "defect";
};
