// Stands in for the real router until the first HTTP routes land. It proves a deployed Worker
// answers and nothing more.
export const respondPlaceholder = (): Response =>
  Response.json({ service: "billet-api", status: "ok" });
