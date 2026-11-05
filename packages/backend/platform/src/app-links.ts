import { inviteCodeAlphabet, inviteCodeLength } from "@billet/contracts-domain/ids";
import { inviteLinkPrefix } from "@billet/contracts-http-api/routes";

/** The iOS app that opens `/i/<code>`: team id and bundle id, as `project.yml` signs it. */
export const appId = "2666YPBJTB.com.mikitahimpel.billet";

const half = inviteCodeLength / 2;
const typedCode = new RegExp(
  `^([${inviteCodeAlphabet}]{${half}})-?([${inviteCodeAlphabet}]{${half}})$`,
);

/** Whether the path is an invite link's, well formed or not. */
export const isInviteLinkPath = (pathname: string) =>
  pathname.startsWith(inviteLinkPrefix) && !pathname.slice(inviteLinkPrefix.length).includes("/");

/** The code as the app takes it, from a link typed in any case, with the hyphen of the grouping. */
export const codeOfInviteLink = (pathname: string): string | undefined => {
  const match = typedCode.exec(pathname.slice(inviteLinkPrefix.length).toUpperCase());
  return match === null ? undefined : `${match[1]}${match[2]}`;
};

// The code only ever holds the alphabet's letters and digits, so it goes into the page unescaped.
// note: no public build exists yet, so the page names no store link; add one per stage when it does.
const invitePage = (code: string | undefined) => `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Join me in Nooki</title>
<style>
:root { color-scheme: light dark; --ink: #2a1a1c; --paper: #fbf5ee; --muted: #7a6a64; }
@media (prefers-color-scheme: dark) { :root { --ink: #f5ebe4; --paper: #1d1416; --muted: #b3a39d; } }
body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 24px;
  box-sizing: border-box; background: var(--paper); color: var(--ink);
  font: 17px/1.4 ui-rounded, -apple-system, system-ui, sans-serif; text-align: center; }
main { max-width: 22rem; }
h1 { font-size: 28px; margin: 0 0 12px; }
p { color: var(--muted); margin: 0 0 24px; }
code { display: block; font: 600 32px/1.2 ui-monospace, monospace; letter-spacing: 0.08em;
  margin: 0 0 16px; }
button { font: inherit; font-weight: 600; padding: 12px 28px; border: 0; border-radius: 999px;
  background: var(--ink); color: var(--paper); }
</style>
</head>
<body>
<main>
<h1>Join me in Nooki</h1>
${
  code === undefined
    ? "<p>This invite link is broken. Ask your person for their code, and enter it in Nooki.</p>"
    : `<p>Open this link on the iPhone that has Nooki, or enter this code in the app.</p>
<code>${code.slice(0, half)} ${code.slice(half)}</code>
<button type="button" id="copy">Copy code</button>
<script>
document.getElementById("copy").addEventListener("click", (event) => {
  navigator.clipboard.writeText("${code}").then(() => { event.target.textContent = "Copied"; });
});
</script>`
}
</main>
</body>
</html>
`;

const pageHeaders = {
  "content-type": "text/html; charset=utf-8",
  "cache-control": "no-store",
  "x-robots-tag": "noindex",
  "referrer-policy": "no-referrer",
  "content-security-policy":
    "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; frame-ancestors 'none'",
};

/**
 * Universal Links: the association file iOS fetches, and the page an invite link opens where the
 * app isn't installed. The page never reads or claims the invite, and nothing here logs the path.
 */
export const respondAppLink = (pathname: string): Response | undefined => {
  if (pathname === "/.well-known/apple-app-site-association") {
    return Response.json({
      applinks: { details: [{ appIDs: [appId], components: [{ "/": `${inviteLinkPrefix}*` }] }] },
    });
  }
  if (isInviteLinkPath(pathname)) {
    return new Response(invitePage(codeOfInviteLink(pathname)), { headers: pageHeaders });
  }
  return undefined;
};
