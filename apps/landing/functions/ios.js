// The short link in the TikTok profile (ourio.app/ios). TikTok's in-app browser won't leave for the App Store on its
// own, by script or by redirect, so it gets the one-screen page at /get/ whose every tap is the App Store link; every
// other browser gets a 302 straight to the listing. Visits are counted from here, as Umami events sent after the
// response so they add no wait: the page view on GET, app_store_click on the redirect or on the page's tap (a POST).

import { appStoreUrl } from "../src/config.ts";

const umami = "https://stats.itsnexis.com/api/e";
const website = "602fa9cd-5bb9-4de9-bc6d-bcdcce04c264";
const tiktokTags = "utm_source=tiktok&utm_medium=social&utm_campaign=profile";
const inTikTok = /musical_ly|BytedanceWebview|TikTok/i;

export function onRequest(context) {
  const { request, env } = context;
  const url = new URL(request.url);
  const tiktok = inTikTok.test(request.headers.get("user-agent") ?? "");
  // ?notrack=1 skips the count: the owner's localStorage opt-out never reaches a server.
  const counted = url.hostname === "ourio.app" && url.searchParams.get("notrack") !== "1";
  const track = (events) => {
    if (counted) context.waitUntil(count(request, url, events).catch(() => {}));
  };
  if (request.method === "POST") {
    track({ click: true });
    return new Response(null, { status: 204 });
  }
  if (request.method === "GET") track({ view: true, click: !tiktok });
  if (tiktok) return env.ASSETS.fetch(new URL("/get/", url));
  return new Response(null, {
    status: 302,
    headers: { location: appStoreUrl, "cache-control": "no-store" },
  });
}

async function count(request, url, { view = false, click = false }) {
  const ua = request.headers.get("user-agent") ?? "";
  const ip = request.headers.get("cf-connecting-ip") ?? "";
  // Umami would see only this Worker's address, so every visitor would share one session. A daily hash of the
  // visitor's address and browser keeps them apart, the way Umami's own salt does; the address is not sent.
  const day = new Date().toISOString().slice(0, 10);
  const id = await sha256(`${website}|${ip}|${ua}|${day}`);
  const page = url.search.includes("utm_source=") ? `/ios${url.search}` : `/ios?${tiktokTags}`;
  const base = {
    website,
    id,
    hostname: "ourio.app",
    url: page,
    title: "Ourio on the App Store",
    referrer: request.headers.get("referer") ?? "",
    language: (request.headers.get("accept-language") ?? "").split(",")[0],
  };
  const headers = { "content-type": "application/json", "user-agent": ua };
  const send = (payload) =>
    fetch(umami, { method: "POST", headers, body: JSON.stringify({ type: "event", payload }) });
  if (view) await send(base);
  if (click) await send({ ...base, name: "app_store_click", data: { where: "tiktok" } });
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest).slice(0, 16)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
