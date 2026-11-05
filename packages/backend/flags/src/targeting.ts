import type { EpochMillis } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { AgeBand, Targeting } from "./experiments.ts";

/** What the server knows about the caller when it picks variants. */
export interface FlagContext {
  readonly pairId: PairId;
  /** `<marketing>+<build>` as the app sent it, or `unknown`. */
  readonly appVersion: string;
  /** Not known until the age gate stores a declared band; then targeting by band applies. */
  readonly ageBand?: AgeBand | undefined;
  /** When the pair formed, if the server still knows. */
  readonly pairedAt?: EpochMillis | undefined;
}

interface ParsedVersion {
  readonly parts: ReadonlyArray<number>;
  readonly build: number | undefined;
}

const parse = (version: string): ParsedVersion | undefined => {
  const match = /^(\d{1,4}(?:\.\d{1,4}){0,3})(?:\+(\d{1,8}))?$/.exec(version);
  if (match === null) return undefined;
  return {
    parts: (match[1] ?? "").split(".").map(Number),
    build: match[2] === undefined ? undefined : Number(match[2]),
  };
};

/**
 * Orders two app versions: negative, zero or positive. Missing parts count as 0 (`1.2` is
 * `1.2.0`). The build is compared only when both name one, so a bound of `1.2` covers every
 * build of 1.2. `undefined` when either is not a version.
 */
export const compareAppVersions = (a: string, b: string): number | undefined => {
  const left = parse(a);
  const right = parse(b);
  if (left === undefined || right === undefined) return undefined;
  for (let index = 0; index < Math.max(left.parts.length, right.parts.length); index += 1) {
    const difference = (left.parts[index] ?? 0) - (right.parts[index] ?? 0);
    if (difference !== 0) return difference;
  }
  if (left.build === undefined || right.build === undefined) return 0;
  return left.build - right.build;
};

/** Whether the rules let this caller in. Each rule given must hold. */
export const isTargeted = (targeting: Targeting, context: FlagContext): boolean => {
  const { minAppVersion, maxAppVersion, ageBands, pairIds, pairedSince } = targeting;
  if (pairedSince !== undefined) {
    if (context.pairedAt === undefined || context.pairedAt < Date.parse(pairedSince)) return false;
  }
  if (pairIds !== undefined && pairIds.length > 0 && !pairIds.includes(context.pairId)) {
    return false;
  }
  if (ageBands !== undefined && ageBands.length > 0) {
    if (context.ageBand === undefined || !ageBands.includes(context.ageBand)) return false;
  }
  if (minAppVersion !== undefined) {
    const order = compareAppVersions(context.appVersion, minAppVersion);
    if (order === undefined || order < 0) return false;
  }
  if (maxAppVersion !== undefined) {
    const order = compareAppVersions(context.appVersion, maxAppVersion);
    if (order === undefined || order > 0) return false;
  }
  return true;
};
