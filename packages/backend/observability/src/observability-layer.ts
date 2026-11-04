import { ErrorReporter, Layer, Logger, Tracer } from "effect";
import { jsonLogger, type LogSink } from "./json-logger.ts";
import { traceLogTracer } from "./trace-log-tracer.ts";

/**
 * The JSON logger, the tracer that writes spans as `trace` lines, and an error reporter that logs
 * a failure the HTTP server could not answer (a defect) once, with its redacted cause and the
 * span it happened in. Typed failures are answered and logged by each route's error handler.
 *
 * Build it once per isolate and reuse it: the tracer keeps the spans of unfinished traces.
 */
export const observabilityLayer = (sink: LogSink): Layer.Layer<never> => {
  const logger = jsonLogger(sink);
  return Layer.mergeAll(
    Logger.layer([logger]),
    Layer.succeed(Tracer.Tracer, traceLogTracer(sink)),
    ErrorReporter.layer([
      ErrorReporter.make(({ cause, fiber, timestamp }) =>
        logger.log({
          message: "unhandled failure",
          logLevel: "Error",
          cause,
          fiber,
          date: new Date(Number(timestamp / 1_000_000n)),
        }),
      ),
    ]),
  );
};
