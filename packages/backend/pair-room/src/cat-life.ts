import type { CatEntry, CatEvent, CatNeeds } from "@billet/contracts-domain/cat";
import type { EpochMillis, UserId } from "@billet/contracts-domain/ids";

/**
 * A port of Swift's `PetLife` with `LifeConfig.standard`: change both together; tests pin them.
 */
export const lifeConfig = {
  floor: 0.2,
  initial: 0.7,
  fullHours: 6,
  lovedHours: 14,
  playfulHours: 10,
  restedAwakeHours: 18,
  restedAsleepHours: 2.5,
  fullAsleepPace: 0.5,
  playfulAsleepPace: 0.3,
  returns: 1.5,
  feedGain: 0.6,
  petGain: 0.2,
  playGain: 0.45,
  noteGain: 0.4,
  playLoveGain: 0.06,
  playTiring: 0.05,
  sleepiestHour: 3,
  rhythmWeight: 0.6,
  tirednessWeight: 0.6,
  sleepAbove: 0.7,
  wakeBelow: 0.5,
  stayUpHours: 0.33,
  loveSharpness: 10,
  missingGap: 0.25,
  fullWeight: 0.2,
  restedWeight: 0.2,
  lovedWeight: 0.4,
  playfulWeight: 0.2,
  stepHours: 0.25,
  horizonHours: 168,
} as const;

/** Swift's `LifeEvent.Kind`, the part of an event the curves read. */
type LifeKind = "feed" | "pet" | "play" | "note" | "sleep" | "shoo";

/** The kind each journal event is to the curves. Watering the plant fills no need. */
export const lifeKindOf = (event: CatEvent): LifeKind | undefined => {
  switch (event._tag) {
    case "Fed":
      return "feed";
    case "Petted":
      return "pet";
    case "Played":
    case "GamePlayed":
      return "play";
    case "NoteShared":
      return "note";
    case "Slept":
      return "sleep";
    case "Shooed":
      return "shoo";
    case "Watered":
      return undefined;
  }
};

export interface LifeContext {
  readonly partners: readonly [UserId, UserId];
  readonly utcOffsetSeconds: number;
  /** When the cat was adopted. Before then nothing falls or rises. */
  readonly bornAt: EpochMillis;
}

interface LifeEvent {
  readonly id: string;
  readonly kind: LifeKind;
  readonly by: string;
  /** Whole seconds, as Swift's `LifeEvent` keeps them. */
  readonly at: number;
}

const gain = (n: number, g: number, k: number): number =>
  Math.min(1, n + g * Math.pow(Math.max(0, 1 - n), k));

const decay = (n: number, floor: number, hours: number, tau: number): number =>
  tau > 0 ? floor + (n - floor) * Math.exp(-hours / tau) : floor;

const sleepiness = (hour: number): number =>
  0.5 + 0.5 * Math.cos((2 * Math.PI * (hour - lifeConfig.sleepiestHour)) / 24);

const softMin = (values: ReadonlyArray<number>, beta: number): number => {
  const low = Math.min(...values);
  const mean = values.reduce((sum, v) => sum + Math.exp(-beta * (v - low)), 0) / values.length;
  return low - Math.log(mean) / beta;
};

// Swift's `fmod`-like `truncatingRemainder`.
const remainder = (a: number, b: number): number => a % b;

/** Swift sorts by time, then by `uuidString`, which is upper case. */
const precedes = (a: LifeEvent, b: LifeEvent): number =>
  a.at !== b.at ? a.at - b.at : a.id < b.id ? -1 : a.id > b.id ? 1 : 0;

class Fold {
  readonly c = lifeConfig;
  full: number = lifeConfig.initial;
  rested: number = lifeConfig.initial;
  playful: number = lifeConfig.initial;
  readonly love = new Map<string, number>();
  asleep = false;
  wokeAt = -Infinity;
  readonly partners: ReadonlyArray<string>;

  constructor(private readonly context: LifeContext) {
    this.partners = [...context.partners].toSorted();
    for (const partner of this.partners) this.love.set(partner, lifeConfig.initial);
  }

  begin(t: number): void {
    this.asleep = this.pressure(t) > this.c.sleepAbove;
  }

  advance(from: number, end: number, step: number): number {
    let t = from;
    while (t < end) {
      const next = Math.min(end, (Math.floor(t / step) + 1) * step);
      this.pass(t, next);
      t = next;
    }
    return Math.max(t, end);
  }

  private pass(t: number, end: number): void {
    const hours = (end - t) / 3600;
    if (!(hours > 0)) return;
    const c = this.c;
    const f = c.floor;
    const fullPace = this.asleep ? c.fullAsleepPace : 1;
    const playPace = this.asleep ? c.playfulAsleepPace : 1;
    this.full = decay(this.full, f, hours * fullPace, c.fullHours);
    this.playful = decay(this.playful, f, hours * playPace, c.playfulHours);
    this.rested = this.asleep
      ? 1 - (1 - this.rested) * Math.exp(-hours / Math.max(c.restedAsleepHours, 1e-6))
      : decay(this.rested, f, hours, c.restedAwakeHours);
    for (const partner of this.partners) {
      this.love.set(partner, decay(this.love.get(partner) ?? c.initial, f, hours, c.lovedHours));
    }
    const p = this.pressure(end);
    if (this.asleep && p < c.wakeBelow) {
      this.asleep = false;
    } else if (!this.asleep && p > c.sleepAbove && end - this.wokeAt >= c.stayUpHours * 3600) {
      this.asleep = true;
    }
  }

  apply(event: LifeEvent): void {
    const c = this.c;
    switch (event.kind) {
      case "feed":
        this.full = gain(this.full, c.feedGain, c.returns);
        break;
      case "pet":
        this.care(event.by, c.petGain);
        break;
      case "play":
        this.playful = gain(this.playful, c.playGain, c.returns);
        this.rested = Math.max(c.floor, this.rested - c.playTiring);
        this.care(event.by, c.playLoveGain);
        break;
      case "note":
        for (const partner of this.partners) this.care(partner, c.noteGain);
        break;
      case "sleep":
        this.asleep = true;
        return;
      case "shoo":
        return;
    }
    this.asleep = false;
    this.wokeAt = event.at;
  }

  // Both partners are always known on the server, so care from anyone else adds nothing.
  private care(by: string, g: number): void {
    const current = this.love.get(by);
    if (current === undefined) return;
    this.love.set(by, gain(current, g, this.c.returns));
  }

  private pressure(t: number): number {
    const local = t + this.context.utcOffsetSeconds;
    const hour = remainder(local, 86400) / 3600;
    const s = sleepiness(hour < 0 ? hour + 24 : hour);
    return this.c.rhythmWeight * s + this.c.tirednessWeight * (1 - this.rested);
  }

  needs(at: EpochMillis): CatNeeds {
    const c = this.c;
    const values = this.partners.map((p) => this.love.get(p) ?? c.floor);
    const loved = softMin(values, c.loveSharpness);
    const weights = [c.fullWeight, c.restedWeight, c.lovedWeight, c.playfulWeight];
    const needs = [this.full, this.rested, loved, this.playful];
    const total = weights.reduce((a, b) => a + b, 0);
    const log = needs.reduce(
      (sum, n, i) => sum + (weights[i] ?? 0) * Math.log(Math.max(n, 1e-6)),
      0,
    );
    const most = Math.max(...values);
    const missing = this.partners.find((p) => most - (this.love.get(p) ?? 0) >= c.missingGap);
    return {
      at,
      full: this.full,
      rested: this.rested,
      loved,
      playful: this.playful,
      mood: Math.exp(log / total),
      asleep: this.asleep,
      ...(missing === undefined ? {} : { missing: missing as UserId }),
    };
  }
}

/** The cat's needs at `now`, from every journal entry up to then. */
export const catNeeds = (
  entries: Iterable<CatEntry>,
  now: EpochMillis,
  context: LifeContext,
): CatNeeds => {
  const c = lifeConfig;
  const fold = new Fold(context);
  const step = Math.max(60, c.stepHours * 3600);
  const end = now / 1000;
  const horizon = end - c.horizonHours * 3600;
  const born = Math.min(context.bornAt, now) / 1000;
  let t = Math.floor(Math.max(horizon, born) / step) * step;
  fold.begin(t);
  const seen = new Set<string>();
  const ordered: LifeEvent[] = [];
  for (const entry of entries) {
    const kind = lifeKindOf(entry.event);
    const at = Math.floor(entry.at / 1000);
    if (kind === undefined || at < t || at > end) continue;
    ordered.push({ id: entry.id.toUpperCase(), kind, by: entry.by, at });
  }
  ordered.sort(precedes);
  for (const event of ordered) {
    if (seen.has(event.id)) continue;
    seen.add(event.id);
    t = fold.advance(t, event.at, step);
    fold.apply(event);
  }
  fold.advance(t, end, step);
  return fold.needs(now);
};

/** How far back the fold reads, so a caller loads only the entries that matter. */
export const lifeHorizonMillis = (lifeConfig.horizonHours + lifeConfig.stepHours) * 3600 * 1000;
