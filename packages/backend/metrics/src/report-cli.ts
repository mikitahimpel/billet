import { buildReport } from "./funnel.ts";
import { utcDay } from "./metrics.ts";
import { formatReport } from "./report-format.ts";
import { readRows } from "./report-source.ts";

/** The variables the report reads. The names are fixed; their values never appear in output. */
export const requiredVariables = [
  "CLOUDFLARE_ACCOUNT_ID",
  "CLOUDFLARE_API_TOKEN",
  "BILLET_D1_DATABASE_ID",
] as const;

export const usage = `Read-only funnel report. Needs ${requiredVariables.join(", ")} in the environment.
Run it with the secrets from Proton Pass, never by typing a token:
  PROTON_PASS_AGENT_REASON="billet metrics report" pp run --env-file .env.pass -- \\
    env BILLET_D1_DATABASE_ID=<database id> pnpm metrics:report
Use an API token that can only read D1. The script sends SELECT statements and nothing else.
`;

/** Produces the report text, or the reason it cannot (naming the variables that are missing). */
export const runReport = async (
  env: Readonly<Record<string, string | undefined>>,
  fetcher: typeof fetch = fetch,
  now: number = Date.now(),
): Promise<{ readonly ok: boolean; readonly text: string }> => {
  const missing = requiredVariables.filter((name) => (env[name] ?? "") === "");
  if (missing.length > 0) {
    return { ok: false, text: `Missing: ${missing.join(", ")}\n\n${usage}` };
  }
  try {
    const { events, flags } = await readRows(
      {
        accountId: env["CLOUDFLARE_ACCOUNT_ID"] ?? "",
        databaseId: env["BILLET_D1_DATABASE_ID"] ?? "",
        apiToken: env["CLOUDFLARE_API_TOKEN"] ?? "",
      },
      fetcher,
    );
    return { ok: true, text: formatReport(buildReport(events, flags, utcDay(now))) };
  } catch (error) {
    return { ok: false, text: `${error instanceof Error ? error.message : "report failed"}\n` };
  }
};
