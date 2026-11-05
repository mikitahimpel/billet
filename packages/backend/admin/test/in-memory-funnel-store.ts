import { Effect } from "effect";
import type { FunnelStore, SavedFunnel } from "../src/funnel-store.ts";

/** The test double for `FunnelStore`. */
export const makeInMemoryFunnelStore = () => {
  const funnels = new Map<string, SavedFunnel>();
  const store: FunnelStore["Service"] = {
    all: Effect.sync(() => [...funnels.values()].toSorted((a, b) => b.createdAt - a.createdAt)),
    save: (funnel) => Effect.sync(() => void funnels.set(funnel.id, funnel)),
    remove: (id) => Effect.sync(() => funnels.delete(id)),
  };
  return { store, funnels };
};
