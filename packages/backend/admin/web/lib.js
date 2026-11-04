// Pure helpers for the admin page: no DOM, so the tests import them as they are.

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** "Nov 3" for a UTC day like "2026-11-03". */
export function fmtDay(day) {
  const [, m, d] = day.split("-");
  return `${MONTHS[Number(m) - 1]} ${Number(d)}`;
}

/**
 * How long ago `ms` was, the way GitHub says it: "just now", "5 minutes ago", "yesterday",
 * "3 days ago", then a date once it is a month old. A future time reads "in 5 minutes".
 */
export function relativeTime(ms, now) {
  if (ms == null) return "never";
  const diff = now - ms;
  const ahead = diff < 0;
  const gap = Math.abs(diff);
  const say = (n, unit) => {
    const text = `${n} ${unit}${n === 1 ? "" : "s"}`;
    return ahead ? `in ${text}` : `${text} ago`;
  };
  if (gap < MINUTE) return "just now";
  if (gap < HOUR) return say(Math.floor(gap / MINUTE), "minute");
  if (gap < DAY) return say(Math.floor(gap / HOUR), "hour");
  const days = Math.floor(gap / DAY);
  if (days === 1) return ahead ? "tomorrow" : "yesterday";
  if (days < 30) return say(days, "day");
  const date = new Date(ms);
  const text = `${MONTHS[date.getUTCMonth()]} ${date.getUTCDate()}`;
  return date.getUTCFullYear() === new Date(now).getUTCFullYear()
    ? `on ${text}`
    : `on ${text}, ${date.getUTCFullYear()}`;
}

/** Orders two cell values: numbers by size, text by locale, empty values always last. */
export function compareValues(a, b) {
  const emptyA = a == null || a === "";
  const emptyB = b == null || b === "";
  if (emptyA || emptyB) return Number(emptyA) - Number(emptyB);
  if (typeof a === "number" && typeof b === "number") return a - b;
  return String(a).localeCompare(String(b), "en", { numeric: true, sensitivity: "base" });
}

/** A sorted copy. `dir` is "asc" or "desc"; empty values stay last either way; ties keep order. */
export function sortRows(rows, value, dir) {
  const sign = dir === "desc" ? -1 : 1;
  return rows
    .map((row, index) => ({ row, index, v: value(row) }))
    .toSorted((x, y) => {
      const emptyX = x.v == null || x.v === "";
      const emptyY = y.v == null || y.v === "";
      if (emptyX || emptyY) return Number(emptyX) - Number(emptyY) || x.index - y.index;
      return sign * compareValues(x.v, y.v) || x.index - y.index;
    })
    .map(({ row }) => row);
}

/** Whether every word of the query appears in the text, ignoring case. A blank query matches. */
export function matchesQuery(text, query) {
  const haystack = String(text).toLowerCase();
  return query
    .toLowerCase()
    .split(/\s+/)
    .filter(Boolean)
    .every((word) => haystack.includes(word));
}

/**
 * The change from the previous period. Counts change in percent; shares (`unit: "pp"`) in
 * percentage points. `none` when either side is missing, or a count rises from zero.
 */
export function deltaOf(current, previous, unit = "pct") {
  if (current == null || previous == null) return { kind: "none", text: "no earlier data" };
  let change;
  let text;
  if (unit === "pp") {
    change = (current - previous) * 100;
    text = `${Math.abs(change).toFixed(1).replace(/\.0$/, "")} pts`;
  } else {
    if (previous === 0) {
      return current === 0
        ? { kind: "flat", text: "no change" }
        : { kind: "none", text: "new this period" };
    }
    change = ((current - previous) / previous) * 100;
    text = `${Math.abs(change)
      .toFixed(Math.abs(change) < 10 ? 1 : 0)
      .replace(/\.0$/, "")}%`;
  }
  if (Math.abs(change) < 0.05) return { kind: "flat", text: "no change" };
  return { kind: change > 0 ? "up" : "down", text: `${change > 0 ? "+" : "−"}${text}` };
}

/**
 * The funnel with each step's conversion from the step before it and from the first counted step.
 * A step with no count (installs) gets no rates, and the next step compares with the last count.
 */
export function funnelSteps(steps) {
  const first = steps.find((step) => step.count != null);
  let before = null;
  return steps.map((step) => {
    if (step.count == null) return { ...step, fromPrevious: null, fromFirst: null };
    const out = {
      ...step,
      fromPrevious: before && before.count ? step.count / before.count : null,
      fromFirst: first && first !== step && first.count ? step.count / first.count : null,
    };
    before = step;
    return out;
  });
}

/** The polyline path of a sparkline in a `w`×`h` box; a missing value breaks the line. */
export function sparkPath(values, w, h, pad = 2) {
  const known = values.filter((v) => v != null);
  if (!known.length) return "";
  const max = Math.max(...known);
  const min = Math.min(0, ...known);
  const span = max - min || 1;
  const x = (i) => (values.length <= 1 ? w / 2 : (i * w) / (values.length - 1));
  const y = (v) => pad + (h - pad * 2) * (1 - (v - min) / span);
  let d = "";
  let pen = false;
  values.forEach((v, i) => {
    if (v == null) {
      pen = false;
      return;
    }
    d += `${pen ? "L" : "M"}${x(i).toFixed(1)},${y(v).toFixed(1)}`;
    pen = true;
  });
  return d;
}

/** An axis maximum of 4 even steps that covers `v`. */
export function niceMax(v) {
  const raw = Math.max(1, v) / 4;
  const mag = 10 ** Math.floor(Math.log10(raw));
  const step = [1, 2, 2.5, 5, 10].map((f) => f * mag).find((x) => x >= raw);
  return Math.max(4, Math.ceil(step) * 4);
}

/** Dotted paths to leaf values: `{ targeting: { pairIds: [] } }` → `{ "targeting.pairIds": [] }`. */
export function flatten(obj, prefix = "", out = {}) {
  if (obj == null || typeof obj !== "object" || Array.isArray(obj)) {
    if (prefix) out[prefix] = obj;
    return out;
  }
  for (const [k, v] of Object.entries(obj)) flatten(v, prefix ? `${prefix}.${k}` : k, out);
  return out;
}

/** What changed between two configs, field by field, in a stable order. */
export function diffConfig(before, after) {
  const a = flatten(before || {});
  const b = flatten(after || {});
  return [...new Set([...Object.keys(a), ...Object.keys(b)])]
    .filter((path) => JSON.stringify(a[path]) !== JSON.stringify(b[path]))
    .map((path) => ({ path, before: a[path], after: b[path] }));
}

/** Each variant's share of the weights, 0 to 1. All zero weights give all zero shares. */
export function splitShares(weights) {
  const total = Object.values(weights).reduce((a, b) => a + Math.max(0, b || 0), 0);
  return Object.fromEntries(
    Object.entries(weights).map(([v, w]) => [v, total ? Math.max(0, w || 0) / total : 0]),
  );
}

/** The buttons an experiment offers in its state: start or stop, then kill or unkill. */
export function experimentActions(config) {
  const out = [];
  if (config.status === "draft" || config.status === "stopped") out.push("start");
  if (config.status === "running") out.push("stop");
  out.push(config.killed ? "unkill" : "kill");
  return out;
}

/** The one pill a flag or experiment shows: killed beats its status. */
export function statePill(config) {
  if (config.killed) return { tone: "bad", text: "killed" };
  if (config.status === "running") return { tone: "good", text: "running" };
  if (config.status === "stopped") return { tone: "muted", text: "stopped" };
  return { tone: "muted", text: config.status };
}

/**
 * Flag changes and service-status changes as one log, newest first. Each row says where it
 * happened (`area`), on what (`subject`) and the action; the source change stays in `change`.
 */
export function mergeAudit(flagChanges, statusChanges) {
  const flags = flagChanges.map((change) => ({
    at: change.at,
    by: change.by,
    area: change.pairId ? "pair" : "flag",
    subject: change.key,
    action: change.action,
    change,
  }));
  const statuses = statusChanges.map((change, i) => ({
    at: change.at,
    by: change.by,
    area: "maintenance",
    subject: `status v${change.version}`,
    action: "save",
    change,
    previous: statusChanges[i + 1]?.status ?? null,
  }));
  return [...flags, ...statuses].toSorted((a, b) => b.at - a.at);
}
