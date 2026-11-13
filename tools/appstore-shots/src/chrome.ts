import { execFileSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const candidates = (): string[] => {
  const found = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
  ];
  for (const base of [
    join(homedir(), ".cache/ms-playwright"),
    join(homedir(), "Library/Caches/ms-playwright"),
  ]) {
    if (!existsSync(base)) continue;
    for (const dir of readdirSync(base)
      .filter((name) => name.startsWith("chromium"))
      .sort()
      .reverse()) {
      for (const sub of [
        "chrome-linux/chrome",
        "chrome-linux/headless_shell",
        "chrome-headless-shell-linux64/chrome-headless-shell",
        "chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
      ]) {
        found.push(join(base, dir, sub));
      }
    }
  }
  return found;
};

/** CHROME, else the first Chrome or Chromium found on this machine (Mac, Linux, or Playwright's cache). */
export const chromePath = (): string => {
  const path = process.env.CHROME ?? candidates().find((candidate) => existsSync(candidate));
  if (!path) throw new Error("no Chrome or Chromium found: set CHROME to its executable");
  return path;
};

/** Renders an HTML file to a PNG of exactly `width` x `height`, at device scale 1. */
export const renderPage = (
  htmlFile: string,
  pngFile: string,
  width: number,
  height: number,
): void => {
  execFileSync(
    chromePath(),
    [
      "--headless",
      "--disable-gpu",
      "--no-sandbox",
      "--hide-scrollbars",
      "--force-device-scale-factor=1",
      "--allow-file-access-from-files",
      "--virtual-time-budget=4000",
      `--window-size=${width},${height}`,
      `--screenshot=${pngFile}`,
      pathToFileURL(htmlFile).href,
    ],
    { stdio: ["ignore", "ignore", "ignore"], timeout: 120_000 },
  );
};
