import { inviteCodeAlphabet, inviteCodeLength } from "@billet/contracts-domain/ids";

/** The iOS app that opens `/i/<code>`: team id and bundle id, as `project.yml` signs it. */
export const appId = "2666YPBJTB.com.mikitahimpel.billet";

const invitePath = new RegExp(`^/i/[${inviteCodeAlphabet}]{${inviteCodeLength}}$`);

/**
 * Universal Links: the association file iOS fetches, and the page an invite link opens where the
 * app isn't installed. The code stays in the path only; nothing here logs or stores it.
 */
export const respondAppLink = (pathname: string): Response | undefined => {
  if (pathname === "/.well-known/apple-app-site-association") {
    return Response.json({
      applinks: { details: [{ appIDs: [appId], components: [{ "/": "/i/*" }] }] },
    });
  }
  if (invitePath.test(pathname)) {
    return new Response("Open this link on the iPhone that has Nooki to join your person.", {
      headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" },
    });
  }
  return undefined;
};
