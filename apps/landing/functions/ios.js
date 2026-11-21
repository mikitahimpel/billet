// The short link in the TikTok profile (ourio.app/ios). A 302 straight to the App Store listing: TikTok's in-app
// browser blocks a page that sends itself there by script, so there is no page to see. The visit is counted from here
// instead, as an Umami page view and app_store_click, sent after the response so it adds no wait.

import { appStoreUrl } from "../src/config.ts";

const umami = "https://stats.itsnexis.com/api/e";
const website = "602fa9cd-5bb9-4de9-bc6d-bcdcce04c264";
const tiktokTags = "utm_source=tiktok&utm_medium=social&utm_campaign=profile";
// ?notrack=1 skips the count: the owner's localStorage opt-out never reaches a server.

export function onRequest(context) {
  const { request } = context;
  const url = new URL(request.url);
  if (
    url.hostname === "ourio.app" &&
    request.method === "GET" &&
    url.searchParams.get("notrack") !== "1"
  ) {
    context.waitUntil(count(request, url).catch(() => {}));
  }
  return new Response(null, {
    status: 302,
    headers: { location: appStoreUrl, "cache-control": "no-store" },
  });
}

async function count(request, url) {
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
  await send(base);
  await send({ ...base, name: "app_store_click", data: { where: "tiktok" } });
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest).slice(0, 16)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
