import { Context, Layer } from "effect";
import { type AppStatus, normalStatus } from "@billet/contracts-http-api/status";

/** Read once per request, before anything touches the database (`app-status-live` in platform).
 * The flags answer carries it, so one launch read gets both. */
export class ServiceStatus extends Context.Service<
  ServiceStatus,
  { readonly current: AppStatus }
>()("@billet/backend-flags/ServiceStatus") {
  static readonly with = (current: AppStatus) => Layer.succeed(ServiceStatus, { current });
  static readonly normal = ServiceStatus.with(normalStatus);
}
