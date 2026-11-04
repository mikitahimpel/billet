// The demo Worker must not load Effect or any @billet package (test/demo-imports.node.test.ts), so
// its trace and log lines are written here by hand, in the shape of the main Worker's
// (docs/observability.md). Only fixed labels and numbers are passed in.

type Level = "info" | "warn" | "error";

const write = (level: Level, line: Record<string, unknown>): void => {
  const json = JSON.stringify({ level, ...line });
  if (level === "error") console.error(json);
  else if (level === "warn") console.warn(json);
  else console.log(json);
};

const hex = (bytes: number): string =>
  Array.from(crypto.getRandomValues(new Uint8Array(bytes)), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");

/** One log line from the demo Worker. `fields` must hold fixed labels and numbers only. */
export const logLine = (
  level: Level,
  message: string,
  fields: Readonly<Record<string, string | number | boolean>> = {},
): void => write(level, { message, ...fields });

/**
 * Runs `run` as a root span named `name` and writes one `trace` line when it ends: ids, `ms`,
 * `status`, the error's class if it threw (never its message), and `attributes`. A throw is
 * rethrown.
 */
export const traced = async <A>(
  name: string,
  attributes: Readonly<Record<string, string>>,
  run: () => Promise<A>,
): Promise<A> => {
  const started = Date.now();
  const ids = { traceId: hex(16), span: name, spanId: hex(8) };
  try {
    const result = await run();
    write("info", { message: "trace", ...ids, ms: Date.now() - started, status: "ok", attributes });
    return result;
  } catch (error) {
    write("error", {
      message: "trace",
      ...ids,
      ms: Date.now() - started,
      status: "error",
      error: error instanceof Error ? error.name : "unknown",
      attributes,
    });
    throw error;
  }
};
