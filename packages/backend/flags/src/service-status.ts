import { Context, Layer } from "effect";
import { type AppStatus, normalStatus } from "@billet/contracts-http-api/status";

/**
 * The service status the Worker read for this request (maintenance, minimum build, notice). The
 * flags answer carries it, so one launch read gets both. Read once, before anything touches the
 * database; see `app-status-live` in the platform package.
 */
export class ServiceStatus extends Context.Service<
  ServiceStatus,
  { readonly current: AppStatus }
>()("@billet/backend-flags/ServiceStatus") {
  static readonly with = (current: AppStatus) => Layer.succeed(ServiceStatus, { current });
  static readonly normal = ServiceStatus.with(normalStatus);
}
