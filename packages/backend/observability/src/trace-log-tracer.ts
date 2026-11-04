import { type Exit, Option, Tracer } from "effect";
import type { LogSink } from "./json-logger.ts";
import { causeLabel, redactField } from "./redact.ts";

/** One finished span, as it appears in a `trace` line. */
export interface SpanRecord {
  readonly name: string;
  readonly spanId: string;
  readonly parentId?: string;
  readonly ms: number;
  readonly status: "ok" | "error";
  readonly error?: string;
  readonly attributes?: Record<string, unknown>;
}

type SpanOptions = ConstructorParameters<typeof Tracer.NativeSpan>[0];

/** A native span that reports itself once, when it ends. */
class ReportingSpan extends Tracer.NativeSpan {
  readonly #onEnd: (span: ReportingSpan, exit: Exit.Exit<unknown, unknown>) => void;

  constructor(
    options: SpanOptions,
    onEnd: (span: ReportingSpan, exit: Exit.Exit<unknown, unknown>) => void,
  ) {
    super(options);
    this.#onEnd = onEnd;
  }

  override end(endTime: bigint, exit: Exit.Exit<unknown, unknown>): void {
    if (this.status._tag === "Ended") return;
    super.end(endTime, exit);
    this.#onEnd(this, exit);
  }
}

/** A span with no parent in this process: a request, a Durable Object call, an alarm. */
const isRoot = (span: Tracer.Span): boolean =>
  Option.match(span.parent, { onNone: () => true, onSome: (parent) => parent._tag !== "Span" });

/** A URL's path and query can hold an id or a media key; the host and route say enough. */
const urlKeys = new Set(["url.full", "url.path", "url.query"]);

/**
 * Left out of a line: the caller's source location, which Effect adds to some spans, the SQL of
 * `@effect/sql` spans, which the repository span above it already names, and URLs.
 */
const isNoise = (key: string): boolean =>
  key.startsWith("code.") || key === "db.query.text" || urlKeys.has(key);

const recordOf = (span: ReportingSpan, exit: Exit.Exit<unknown, unknown>): SpanRecord => {
  const ended = span.status._tag === "Ended" ? span.status.endTime : span.startTime;
  const attributes: Record<string, unknown> = {};
  for (const [key, value] of span.attributes) {
    if (!isNoise(key)) attributes[key] = redactField(key, value);
  }
  const parentId = Option.getOrUndefined(span.parent)?.spanId;
  return {
    name: span.name,
    spanId: span.spanId,
    ...(parentId === undefined ? {} : { parentId }),
    ms: Math.round(Number(ended - span.startTime) / 1e5) / 10,
    status: exit._tag === "Success" ? "ok" : "error",
    ...(exit._tag === "Failure" ? { error: causeLabel(exit.cause) } : {}),
    ...(Object.keys(attributes).length === 0 ? {} : { attributes }),
  };
};

/** A top-level line names its span `span`, as every log line inside it does. */
const withoutName = ({ name: _name, ...rest }: SpanRecord): Omit<SpanRecord, "name"> => rest;

/** Spans kept per trace; the rest are counted. Bounds a runaway loop's line. */
const maxSpansPerTrace = 100;
/** Traces whose root has not ended. A root that never ends (a crash) is dropped past this. */
const maxOpenTraces = 500;

/**
 * Effect's native tracer, made to write its spans as log lines: Workers traces cannot carry
 * Effect's spans, but Workers Logs indexes JSON fields, so the spans land there.
 *
 * Each root span (the request, a Durable Object call, an alarm) writes one `trace` line when it
 * ends, holding its own name, ids, duration, status and attributes, and every child span that
 * ended before it under `spans`. A child that ends after its root (forked follow-up work) gets a
 * `span` line of its own. Attributes pass through `redactField`.
 */
export const traceLogTracer = (sink: LogSink): Tracer.Tracer => {
  const open = new Map<string, { spans: Array<SpanRecord>; dropped: number }>();

  const ended = (span: ReportingSpan, exit: Exit.Exit<unknown, unknown>): void => {
    const record = recordOf(span, exit);
    const trace = open.get(span.traceId);
    if (isRoot(span)) {
      open.delete(span.traceId);
      const level = record.status === "ok" ? "info" : "error";
      sink(
        level,
        JSON.stringify({
          level,
          message: "trace",
          traceId: span.traceId,
          span: record.name,
          ...withoutName(record),
          spans: trace?.spans ?? [],
          ...(trace !== undefined && trace.dropped > 0 ? { droppedSpans: trace.dropped } : {}),
        }),
      );
      return;
    }
    if (trace === undefined) {
      const level = record.status === "ok" ? "info" : "warn";
      sink(
        level,
        JSON.stringify({
          level,
          message: "span",
          traceId: span.traceId,
          span: record.name,
          ...withoutName(record),
        }),
      );
    } else if (trace.spans.length < maxSpansPerTrace) {
      trace.spans.push(record);
    } else {
      trace.dropped += 1;
    }
  };

  return Tracer.make({
    span: (options) => {
      const span = new ReportingSpan(options, ended);
      if (isRoot(span)) {
        if (open.size >= maxOpenTraces) {
          const oldest = open.keys().next();
          if (oldest.done !== true) open.delete(oldest.value);
        }
        open.set(span.traceId, { spans: [], dropped: 0 });
      }
      return span;
    },
  });
};
