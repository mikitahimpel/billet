// The short link in the TikTok and Instagram profiles (ourio.app/ios). Their in-app browsers won't leave for the App
// Store on their own (TikTok refuses even a tapped link), so they get the one-screen page at /get/, told which app it is
// in so its steps name that app's menu; every other browser gets a 302 straight to the listing. Visits are counted from here, as Umami events sent after the
// response so they add no wait: the page view on GET, app_store_click on the redirect or on the page's tap (a POST).

import { appStoreUrl } from "../src/config.ts";

const umami = "https://stats.itsnexis.com/api/e";
const website = "602fa9cd-5bb9-4de9-bc6d-bcdcce04c264";
// menu: the item in the app's ··· menu that opens the page in the phone's browser. store: where the page's links go.
// TikTok blocks App Store links, so its page asks iOS to reopen /ios in Safari; Instagram is given the listing itself.
const inApps = [
  {
    name: "tiktok",
    label: "TikTok",
    ua: /musical_ly|BytedanceWebview|TikTok/i,
    menu: "Open in browser",
    store: "x-safari-https://ourio.app/ios?from=tiktok",
  },
  {
    name: "instagram",
    label: "Instagram",
    ua: /Instagram/i,
    menu: "Open in external browser",
    store: appStoreUrl,
  },
];

export function onRequest(context) {
  const { request, env } = context;
  const url = new URL(request.url);
  const ua = request.headers.get("user-agent") ?? "";
  const app = inApps.find((a) => a.ua.test(ua));
  // ?from=<app> is the page's tap reopened in the phone's browser: the view and the tap were counted in the app already.
  const from = app?.name ?? url.searchParams.get("from") ?? "direct";
  // ?notrack=1 skips the count: the owner's localStorage opt-out never reaches a server.
  const counted = url.hostname === "ourio.app" && url.searchParams.get("notrack") !== "1";
  const track = (events) => {
    if (counted) context.waitUntil(count(request, url, from, events).catch(() => {}));
  };
  if (request.method === "POST") {
    track({ click: true });
    return new Response(null, { status: 204 });
  }
  const escaped = !app && url.searchParams.has("from");
  if (request.method === "GET") track(escaped ? { escaped: true } : { view: true, click: !app });
  if (app) return page(env, url, app);
  return new Response(null, {
    status: 302,
    headers: { location: appStoreUrl, "cache-control": "no-store" },
  });
}

async function page(env, url, app) {
  const res = await env.ASSETS.fetch(new URL("/get/", url));
  return new HTMLRewriter()
    .on("[data-app]", { element: (e) => e.setInnerContent(app.label) })
    .on("[data-menu]", { element: (e) => e.setInnerContent(app.menu) })
    .on("a[data-store]", { element: (e) => e.setAttribute("href", app.store) })
    .transform(res);
}

async function count(request, url, from, { view = false, click = false, escaped = false }) {
  const ua = request.headers.get("user-agent") ?? "";
  const ip = request.headers.get("cf-connecting-ip") ?? "";
  // Umami would see only this Worker's address, so every visitor would share one session. A daily hash of the
  // visitor's address and browser keeps them apart, the way Umami's own salt does; the address is not sent.
  const day = new Date().toISOString().slice(0, 10);
  const id = await sha256(`${website}|${ip}|${ua}|${day}`);
  const tags = `utm_source=${from}&utm_medium=social&utm_campaign=profile`;
  const path = url.search.includes("utm_source=") ? `/ios${url.search}` : `/ios?${tags}`;
  const base = {
    website,
    id,
    hostname: "ourio.app",
    url: path,
    title: "Ourio on the App Store",
    referrer: request.headers.get("referer") ?? "",
    language: (request.headers.get("accept-language") ?? "").split(",")[0],
  };
  const headers = { "content-type": "application/json", "user-agent": ua };
  const send = (payload) =>
    fetch(umami, { method: "POST", headers, body: JSON.stringify({ type: "event", payload }) });
  if (view) await send(base);
  if (click) await send({ ...base, name: "app_store_click", data: { where: from } });
  if (escaped) await send({ ...base, name: "opened_in_browser", data: { where: from } });
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest).slice(0, 16)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
