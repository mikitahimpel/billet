import { Context, Layer } from "effect";
import { appleRootCaG3 } from "./apple-root-certificates.ts";
import { decodeRoot } from "./app-store-signed-data.ts";

/** Where an App Store transaction was made. `Mock` is the dev stage's mock route. */
export type PurchaseEnvironment = "Production" | "Sandbox" | "Xcode" | "Mock";

export interface PaymentsSettings {
  /** The App Store environments whose transactions are credited. */
  readonly environments: ReadonlyArray<PurchaseEnvironment>;
  /**
   * The dev stage's extras: Xcode StoreKit testing transactions, the mock purchase route, and
   * demo-room callers with no session. Off everywhere else.
   */
  readonly devTools: boolean;
  /** The roots an App Store chain must end in, as DER. Tests pass their own. */
  readonly roots: ReadonlyArray<Uint8Array>;
}

/**
 * Which purchases this deployment accepts, by Alchemy stage. `dev` takes Sandbox (a development
 * build) and Xcode (StoreKit testing) and has the dev extras. Every other stage, `prod` included,
 * takes Production and Sandbox, since TestFlight buys in the sandbox.
 */
export const settingsForStage = (
  stage: string | undefined,
  roots: ReadonlyArray<Uint8Array> = [decodeRoot(appleRootCaG3)],
): PaymentsSettings =>
  stage === "dev"
    ? { environments: ["Sandbox", "Xcode"], devTools: true, roots }
    : { environments: ["Production", "Sandbox"], devTools: false, roots };

export class PaymentsConfig extends Context.Service<PaymentsConfig, PaymentsSettings>()(
  "@billet/backend-payments/PaymentsConfig",
) {
  static readonly with = (settings: PaymentsSettings) => Layer.succeed(PaymentsConfig, settings);
}
