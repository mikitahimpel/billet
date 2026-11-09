import { ErrorReporter, Layer, Logger, Tracer } from "effect";
import { jsonLogger, type LogSink } from "./json-logger.ts";
import { traceLogTracer } from "./trace-log-tracer.ts";

/**
 * Logs each defect once with its redacted cause. Build once per isolate: the tracer holds state.
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
