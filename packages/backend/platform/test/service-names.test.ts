import { describe, expect, it } from "vitest";
import { apiWorkerName, serviceName } from "../src/service-names.ts";

describe("apiWorkerName", () => {
  it("is the service name on prod, so the workers.dev address is the service", () => {
    expect(apiWorkerName("ourio", "prod")).toBe("ourio-api");
    expect(apiWorkerName("ourio", "prod")).toBe(serviceName("ourio"));
  });

  it("suffixes every other stage", () => {
    expect(apiWorkerName("ourio", "dev")).toBe("ourio-api-dev");
    expect(apiWorkerName("billet", "dev")).toBe("billet-api-dev");
    expect(apiWorkerName("ourio", "preview")).toBe("ourio-api-preview");
  });

  it("carries no random suffix", () => {
    expect(apiWorkerName("ourio", "dev")).toMatch(/^[a-z]+-api(-[a-z]+)?$/);
  });
});
