import { describe, expect, it } from "vitest";
import { questionCatalog } from "../src/question-catalog.ts";
import raw from "../src/question-catalog.json" with { type: "json" };

describe("question catalog", () => {
  it("has a version that matches its questions", async () => {
    const digest = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(JSON.stringify(raw.questions)),
    );
    const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
    expect(raw.version, "run `pnpm --filter @billet/backend-guess catalog:version`").toBe(
      hex.slice(0, 16),
    );
  });

  it("gives every question its own id", () => {
    const ids = questionCatalog.questions.map((question) => question.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("has enough questions for a round, each with four different options", () => {
    expect(questionCatalog.questions.length).toBeGreaterThanOrEqual(5);
    for (const question of questionCatalog.questions) {
      expect(new Set(question.options).size, `question ${question.id}`).toBe(4);
    }
  });
});
