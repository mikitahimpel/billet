// Stands in for the real router: it proves a deployed Worker answers, and nothing more.
export const respondPlaceholder = (stack = "ourio"): Response =>
  Response.json({ service: `${stack}-api`, status: "ok" });
