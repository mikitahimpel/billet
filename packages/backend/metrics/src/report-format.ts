import type { FunnelReport, Share } from "./funnel.ts";

const percent = (value: number | undefined) =>
  value === undefined ? "-" : `${(value * 100).toFixed(0)}%`;

const shareText = (value: Share): string =>
  value.interval === undefined
    ? "- (no pairs yet)"
    : `${value.count}/${value.of} = ${percent(value.share)} (95% ${percent(value.interval.low)} to ${percent(value.interval.high)})`;

const duration = (millis: number | undefined): string => {
  if (millis === undefined) return "-";
  const minutes = millis / 60_000;
  if (minutes < 90) return `${minutes.toFixed(0)} min`;
  const hours = minutes / 60;
  return hours < 48 ? `${hours.toFixed(1)} h` : `${(hours / 24).toFixed(1)} days`;
};

/** The report as plain text, for the terminal. */
export const formatReport = (report: FunnelReport): string => {
  const lines: Array<string> = [];
  const add = (line = "") => lines.push(line);

  add(`billet funnel, up to ${report.today} (UTC days)`);
  add("Counts are people and pairs. No note, image or text is stored or read.");
  add();
  add("Funnel");
  add(`  invites made (people)            ${report.invitesCreated}`);
  add(`  of them now in a pair            ${shareText(report.inviterPaired)}`);
  add(`  pairs formed                     ${report.pairsFormed}`);
  add(`  widget added by both             ${shareText(report.widgetAddedByBoth)}`);
  add(`  a note sent each way             ${shareText(report.firstNoteBothWays)}`);
  add(`  median time to first note        ${duration(report.medianToFirstNote)}`);
  add(`  median time until both sent one  ${duration(report.medianToFirstNoteBothWays)}`);
  add();
  add("Both partners active, N days after the pair formed");
  for (const day of report.days) {
    const mark = day.day === 7 ? "  <- north star" : "";
    add(`  day ${String(day.day).padEnd(2)} sent a note  ${shareText(day.bothSentNote)}${mark}`);
    add(`  day ${String(day.day).padEnd(2)} note or open ${shareText(day.bothActive)}`);
  }
  add();
  add(
    `Notes per pair per day, first 7 days: ${report.notesPerPairPerDay.mean === undefined ? "-" : report.notesPerPairPerDay.mean.toFixed(2)} (over ${report.notesPerPairPerDay.pairs} pairs at least 7 days old)`,
  );
  const watchedShare = report.opening.watched + report.opening.skipped;
  add(
    `Opening: watched ${report.opening.watched}, skipped ${report.opening.skipped}${watchedShare === 0 ? "" : ` (${percent(report.opening.watched / watchedShare)} watched)`}`,
  );
  if (report.daily.length > 0) {
    add();
    add("Notes per day");
    for (const row of report.daily.slice(-14)) {
      add(`  ${row.day}  ${String(row.notes).padStart(4)} notes in ${row.pairsWithNote} pairs`);
    }
  }
  for (const experiment of report.experiments) {
    add();
    add(`Experiment ${experiment.key}: both partners sent a note on day 7`);
    for (const variant of experiment.variants) {
      add(
        `  ${variant.variant.padEnd(16)} ${String(variant.pairs).padStart(4)} pairs  ${shareText(variant.northStar)}  to first note ${duration(variant.medianToFirstNote)}`,
      );
    }
    add(`  ${experiment.caution}`);
  }
  return `${lines.join("\n")}\n`;
};
