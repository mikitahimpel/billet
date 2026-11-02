import { runReport } from "../src/report-cli.ts";

declare const process: {
  readonly env: Record<string, string | undefined>;
  exitCode?: number;
};

const { ok, text } = await runReport(process.env);
console.log(text);
if (!ok) process.exitCode = 1;
