import { describe, expect, it } from "vitest";
import { admitFrame, maxFramesPerSecond, type FrameWindow } from "../src/frame-window.ts";

const send = (count: number, at: (i: number) => number, from?: FrameWindow) => {
  let window = from;
  let admitted = 0;
  for (let i = 0; i < count; i += 1) {
    const next = admitFrame(window, at(i));
    window = next.window;
    if (next.admitted) admitted += 1;
  }
  return { window, admitted };
};

describe("frame window", () => {
  it("admits the budget within one second and drops the rest", () => {
    expect(send(100, (i) => 1_000 + i).admitted).toBe(maxFramesPerSecond);
  });

  it("starts a new budget a second after the window opened", () => {
    const first = send(100, () => 1_000);
    expect(send(10, () => 2_000, first.window).admitted).toBe(10);
  });

  it("admits a steady 40 ms points stream with room to spare", () => {
    expect(send(250, (i) => i * 40).admitted).toBe(250);
  });

  it("restarts when the clock goes backwards", () => {
    const full = send(100, () => 5_000);
    expect(admitFrame(full.window, 4_000).admitted).toBe(true);
  });
});
