import { clientHeaders } from "./routes.ts";

/** What a missing or malformed build or system reads as. */
export const unknownClient = "unknown";

const appVersionPattern = /^\d{1,4}(\.\d{1,4}){0,3}(\+\d{1,8})?$/;
const osPattern = /^(iOS|iPadOS|macOS) \d{1,3}(\.\d{1,3}){0,2}$/;

export interface ClientInfo {
  /** `<marketing>+<build>`, such as `1.2.0+14`, or `unknown`. */
  readonly appVersion: string;
  /** Such as `iOS 26.1`, or `unknown`. */
  readonly os: string;
}

/** Anything not exactly the documented shape is `unknown`, so no free text gets further. */
export const clientInfoOf = (headers: Readonly<Record<string, string | undefined>>): ClientInfo => {
  const appVersion = headers[clientHeaders.appVersion]?.trim() ?? "";
  const os = headers[clientHeaders.os]?.trim() ?? "";
  return {
    appVersion: appVersionPattern.test(appVersion) ? appVersion : unknownClient,
    os: osPattern.test(os) ? os : unknownClient,
  };
};
