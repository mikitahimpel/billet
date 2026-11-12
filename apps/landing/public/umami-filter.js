// Umami bot filter, loaded before s.js. The first day's sessions on ourio.app were mostly headless renders:
// Windows 800x600, "iPhones" with a 1920x1080 screen and an en-US@posix language. Dropped visits never reach
// Umami; the rest carry a tag of coarse browser traits so a new fleet can be told apart and filtered too.
window.umamiBeforeSend = function (type, payload) {
  var n = navigator;
  var ua = n.userAgent;
  if (n.webdriver || payload.screen === "800x600" || payload.screen === "1280x1200") return false;
  if (/@posix/.test(n.language || "")) return false;
  // No iPhone has a 1920-wide screen, and every iOS browser is WebKit, which has no userAgentData.
  if (/iPhone|iPad/.test(ua) && (n.userAgentData || (payload.screen || "").startsWith("1920x")))
    return false;
  // Real Chrome on Android always has window.chrome.
  if (/Android.*Chrome\//.test(ua) && !/; wv\)|SamsungBrowser/.test(ua) && !window.chrome)
    return false;
  // Firefox has no userAgentData, and real Edge always lists itself among its brands.
  var brands = n.userAgentData
    ? n.userAgentData.brands
        .map(function (b) {
          return b.brand;
        })
        .join(",")
    : "";
  if (/Firefox\//.test(ua) && n.userAgentData) return false;
  if (/Edg\//.test(ua) && brands && brands.indexOf("Microsoft Edge") < 0) return false;
  payload.tag = [
    "l" + (n.languages ? n.languages.length : 0),
    "p" + (n.plugins && n.plugins.length ? 1 : 0),
    "t" + (n.maxTouchPoints ? 1 : 0),
    "o" + (window.outerWidth ? 1 : 0),
    "c" + (window.chrome ? 1 : 0),
    "u" + (n.userAgentData ? 1 : 0),
    "b" +
      (/Google Chrome/.test(brands)
        ? "g"
        : /Microsoft Edge/.test(brands)
          ? "e"
          : /Headless/.test(brands)
            ? "h"
            : brands
              ? "o"
              : "-"),
  ].join("");
  return payload;
};

// A page view counts only after the visitor scrolls, clicks, taps or types (the tag has
// data-auto-pageview="false"): headless renders open one page and leave without touching it.
(function () {
  var events = ["scroll", "pointerdown", "keydown", "touchstart"];
  var opts = { capture: true, passive: true };
  var sent = false;
  function send() {
    if (window.umami) return window.umami.track();
    var s = document.querySelector('script[src="https://stats.itsnexis.com/s.js"]');
    if (s)
      s.addEventListener(
        "load",
        function () {
          if (window.umami) window.umami.track();
        },
        { once: true },
      );
  }
  function engage() {
    if (sent) return;
    sent = true;
    events.forEach(function (e) {
      removeEventListener(e, engage, opts);
    });
    send();
  }
  events.forEach(function (e) {
    addEventListener(e, engage, opts);
  });
})();
