import { inviteCodeAlphabet, inviteCodeLength } from "@billet/contracts-domain/ids";
import { inviteLinkPrefix } from "@billet/contracts-http-api/routes";

/** Team id and bundle id, as `project.yml` signs it, then the first App Store app's, whose
 * installed builds still open invite links until the owner retires it. */
export const appIds = ["2666YPBJTB.com.ourio.app", "2666YPBJTB.com.mikitahimpel.billet"] as const;

const half = inviteCodeLength / 2;
const typedCode = new RegExp(
  `^([${inviteCodeAlphabet}]{${half}})-?([${inviteCodeAlphabet}]{${half}})$`,
);

/** Well formed or not. */
export const isInviteLinkPath = (pathname: string) =>
  pathname.startsWith(inviteLinkPrefix) && !pathname.slice(inviteLinkPrefix.length).includes("/");

/** From a link typed in any case, with the hyphen of the grouping. */
export const codeOfInviteLink = (pathname: string): string | undefined => {
  const match = typedCode.exec(pathname.slice(inviteLinkPrefix.length).toUpperCase());
  return match === null ? undefined : `${match[1]}${match[2]}`;
};

/** Ourio on the App Store, for every stage: there is one store app. */
export const appStoreId = "6832707480";
export const appStoreUrl = `https://apps.apple.com/app/id${appStoreId}`;

/** The app's own scheme (`DeepLink.invite`), for a phone that has Ourio but opened the link in Safari. */
const appInviteUrl = (code: string) => `ourio://invite/${code}`;

// The code only ever holds the alphabet's letters and digits, so it goes into the page unescaped.
const invitePage = (code: string | undefined) => `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<meta name="apple-itunes-app" content="app-id=${appStoreId}${
  code === undefined ? "" : `, app-argument=${appInviteUrl(code)}`
}">
<meta property="og:title" content="Join me in Ourio">
<meta property="og:description" content="Open this link on your iPhone to pair with me in Ourio.">
<title>Join me in Ourio</title>
<style>
:root { color-scheme: light dark; --ink: #2a1a1c; --paper: #fbf5ee; --muted: #7a6a64; }
@media (prefers-color-scheme: dark) { :root { --ink: #f5ebe4; --paper: #1d1416; --muted: #b3a39d; } }
body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 24px;
  box-sizing: border-box; background: var(--paper); color: var(--ink);
  font: 17px/1.4 ui-rounded, -apple-system, system-ui, sans-serif; text-align: center; }
main { max-width: 22rem; display: grid; gap: 12px; }
h1 { font-size: 28px; margin: 0; }
p { color: var(--muted); margin: 0 0 12px; }
code { display: block; font: 600 32px/1.2 ui-monospace, monospace; letter-spacing: 0.08em;
  margin: 0 0 4px; }
a, button { font: inherit; font-weight: 600; padding: 12px 28px; border-radius: 999px;
  text-decoration: none; display: block; }
.primary { border: 0; background: var(--ink); color: var(--paper); }
.quiet { border: 1.5px solid var(--ink); background: transparent; color: var(--ink); }
</style>
</head>
<body>
<main>
<h1>Join me in Ourio</h1>
${
  code === undefined
    ? `<p>This invite link is broken. Ask your person for their code, and enter it in Ourio.</p>
<a class="primary" href="${appStoreUrl}">Get Ourio on the App Store</a>`
    : `<p>Get Ourio on your iPhone: it picks up this invite when it opens. Or enter this code in the app.</p>
<code>${code.slice(0, half)} ${code.slice(half)}</code>
<a class="primary" id="get" href="${appStoreUrl}">Get Ourio on the App Store</a>
<a class="quiet" href="${appInviteUrl(code)}">I have Ourio: open it</a>
<button type="button" class="quiet" id="copy">Copy code</button>
<script>
// Ourio's first launch offers the link it finds on the clipboard, so the code survives the install.
document.getElementById("get").addEventListener("click", (event) => {
  event.preventDefault();
  const store = event.currentTarget.href;
  navigator.clipboard.writeText(location.origin + "${inviteLinkPrefix}${code}")
    .finally(() => { location.href = store; });
});
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

/** The invite page never reads or claims the invite, and nothing here logs the path. */
export const respondAppLink = (pathname: string): Response | undefined => {
  if (pathname === "/.well-known/apple-app-site-association") {
    return Response.json(
      {
        applinks: { details: [{ appIDs: appIds, components: [{ "/": `${inviteLinkPrefix}*` }] }] },
      },
      { headers: { "cache-control": "max-age=3600" } },
    );
  }
  if (isInviteLinkPath(pathname)) {
    return new Response(invitePage(codeOfInviteLink(pathname)), { headers: pageHeaders });
  }
  return undefined;
};
