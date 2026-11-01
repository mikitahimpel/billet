import { DurableObject } from "cloudflare:workers";

// Placeholder for the `PairRoom` Durable Object, so the namespace exists on the first deploy.
// The reducer and the real adapter replace it in the PairRoom ticket.
export class PairRoom extends DurableObject {
  override fetch(): Response {
    return new Response("PairRoom is not implemented yet", { status: 501 });
  }
}
