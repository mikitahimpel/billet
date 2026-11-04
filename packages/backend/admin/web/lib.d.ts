// Types for web/lib.js, so the tests can import it under the strict compiler settings.

export interface Delta {
  readonly kind: "up" | "down" | "flat" | "none";
  readonly text: string;
}

export interface FunnelInput {
  readonly step: string;
  readonly label: string;
  readonly count: number | null;
}

export type FunnelOutput<T extends FunnelInput> = T & {
  readonly fromPrevious: number | null;
  readonly fromFirst: number | null;
};

export interface ConfigLike {
  readonly status: string;
  readonly killed: boolean;
}

export interface AuditRow {
  readonly at: number;
  readonly by: string;
  readonly area: "flag" | "pair" | "maintenance";
  readonly subject: string;
  readonly action: string;
  readonly change: unknown;
  readonly previous?: unknown;
}

export function fmtDay(day: string): string;
export function relativeTime(ms: number | null | undefined, now: number): string;
export function compareValues(a: unknown, b: unknown): number;
export function sortRows<T>(
  rows: ReadonlyArray<T>,
  value: (row: T) => unknown,
  dir: "asc" | "desc",
): Array<T>;
export function matchesQuery(text: string, query: string): boolean;
export function deltaOf(
  current: number | null,
  previous: number | null,
  unit?: "pct" | "pp",
): Delta;
export function funnelSteps<T extends FunnelInput>(steps: ReadonlyArray<T>): Array<FunnelOutput<T>>;
export function sparkPath(
  values: ReadonlyArray<number | null>,
  w: number,
  h: number,
  pad?: number,
): string;
export function niceMax(v: number): number;
export function flatten(
  obj: unknown,
  prefix?: string,
  out?: Record<string, unknown>,
): Record<string, unknown>;
export function diffConfig(
  before: unknown,
  after: unknown,
): Array<{ path: string; before: unknown; after: unknown }>;
export function splitShares(weights: Readonly<Record<string, number>>): Record<string, number>;
export function experimentActions(config: ConfigLike): Array<"start" | "stop" | "kill" | "unkill">;
export function statePill(config: ConfigLike): { tone: "good" | "muted" | "bad"; text: string };
export function mergeAudit(
  flagChanges: ReadonlyArray<{
    at: number;
    by: string;
    key: string;
    action: string;
    pairId?: string | null;
  }>,
  statusChanges: ReadonlyArray<{ at: number; by: string; version: number; status: unknown }>,
): Array<AuditRow>;
