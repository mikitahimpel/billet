import { Context, Logger, type LogLevel, References, Tracer } from "effect";
import { redact, redactField, summarizeCause } from "./redact.ts";

export type SinkLevel = "debug" | "info" | "warn" | "error";

/** The Worker passes the console, so Workers Logs indexes the JSON; tests pass an array. */
export type LogSink = (level: SinkLevel, line: string) => void;

const sinkLevel = (level: LogLevel.LogLevel): SinkLevel => {
  switch (level) {
    case "Fatal":
    case "Error":
      return "error";
    case "Warn":
      return "warn";
    case "Info":
      return "info";
    default:
      return "debug";
  }
};

/** Fields the logger writes itself; an annotation with one of these names is dropped. */
const reserved = new Set(["level", "message", "data", "traceId", "spanId", "span", "cause"]);

/** The span a log line belongs to, unless it came from another system. */
const spanOf = (context: Context.Context<never>): Tracer.Span | undefined => {
  const span = Context.getOrUndefined(context, Tracer.ParentSpan);
  return span?._tag === "Span" ? span : undefined;
};

/**
 * One JSON object per log call. Everything but the ids passes through `redact`.
 */
export const jsonLogger = (sink: LogSink): Logger.Logger<unknown, void> =>
  Logger.make(({ message, logLevel, cause, fiber }) => {
    const parts: ReadonlyArray<unknown> = Array.isArray(message) ? message : [message];
    const [first, ...rest] = parts;
    const level = sinkLevel(logLevel);
    const line: Record<string, unknown> = {
      level,
      message: typeof first === "string" ? redact(first) : "",
    };
    const data = typeof first === "string" ? rest : parts;
    if (data.length > 0) line["data"] = data.length === 1 ? redact(data[0]) : redact(data);

    const span = spanOf(fiber.context);
    if (span !== undefined) {
      line["traceId"] = span.traceId;
      line["spanId"] = span.spanId;
      line["span"] = span.name;
    }
    for (const [key, value] of Object.entries(fiber.getRef(References.CurrentLogAnnotations))) {
      if (!reserved.has(key)) line[key] = redactField(key, value);
    }
    if (cause.reasons.length > 0) line["cause"] = summarizeCause(cause);
    sink(level, JSON.stringify(line));
  });
