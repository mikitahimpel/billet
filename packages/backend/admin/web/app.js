"use strict";

(() => {
  const SVGNS = "http://www.w3.org/2000/svg";
  const main = document.getElementById("main");
  const toastEl = document.getElementById("toast");
  const MONTHS = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ];
  const DOM_PROPS = new Set(["value", "checked", "selected", "disabled", "required", "open"]);

  function setProps(el, props) {
    if (!props) return;
    for (const [k, v] of Object.entries(props)) {
      if (v == null || v === false) continue;
      if (k === "text") el.textContent = String(v);
      else if (k === "class") el.setAttribute("class", v);
      else if (k === "style")
        for (const [p, val] of Object.entries(v)) el.style.setProperty(p, val);
      else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
      else if (DOM_PROPS.has(k)) el[k] = v;
      else el.setAttribute(k, v === true ? "" : String(v));
    }
  }

  function append(el, kids) {
    for (const kid of kids.flat(Infinity)) {
      if (kid == null || kid === false) continue;
      el.append(typeof kid === "object" ? kid : String(kid));
    }
    return el;
  }

  const h = (tag, props, ...kids) => {
    const el = document.createElement(tag);
    setProps(el, props);
    return append(el, kids);
  };
  const s = (tag, props, ...kids) => {
    const el = document.createElementNS(SVGNS, tag);
    setProps(el, props);
    return append(el, kids);
  };

  class ApiError extends Error {
    constructor(status, body) {
      super((body && body.message) || `Request failed (${status})`);
      this.status = status;
      this.body = body;
    }
  }

  async function api(path, { method = "GET", body } = {}) {
    const init = { method, credentials: "same-origin", headers: { accept: "application/json" } };
    if (method !== "GET") init.headers["content-type"] = "application/json";
    if (body !== undefined) init.body = JSON.stringify(body);
    let res;
    try {
      res = await fetch(`/admin/api${path}`, init);
    } catch {
      throw new ApiError(0, {
        message: "Can't reach the server. Check your connection and try again.",
      });
    }
    let data = null;
    const text = res.status === 204 ? "" : await res.text();
    if (text) {
      try {
        data = JSON.parse(text);
      } catch {
        data = null;
      }
    }
    if (!res.ok) throw new ApiError(res.status, data);
    return data;
  }

  const enc = encodeURIComponent;

  function errorText(err) {
    if (err instanceof ApiError) {
      if (err.status === 403) return "Not authorised through Cloudflare Access.";
      if (err.status === 404) return "Not found.";
      return err.message;
    }
    return "Something went wrong in the page. Reload and try again.";
  }

  const fmtNum = (n) => (n == null ? "—" : n.toLocaleString("en-US", { maximumFractionDigits: 2 }));
  const fmtPct = (x, digits = 1) =>
    x == null ? "—" : `${(x * 100).toFixed(digits).replace(/\.0$/, "")}%`;
  const fmtInterval = (i) => (i ? `${fmtPct(i.low, 0)}–${fmtPct(i.high, 0)}` : "no interval yet");
  const timeFmt = new Intl.DateTimeFormat("en-US", { dateStyle: "medium", timeStyle: "short" });
  const fmtWhen = (ms) => (ms == null ? "—" : timeFmt.format(ms));
  const fmtDay = (day) => {
    const [, m, d] = day.split("-");
    return `${MONTHS[Number(m) - 1]} ${Number(d)}`;
  };

  function fmtDuration(ms) {
    if (ms == null) return "—";
    const min = Math.round(ms / 60000);
    if (min < 1) return "under 1 min";
    const d = Math.floor(min / 1440);
    const hr = Math.floor((min % 1440) / 60);
    const m = min % 60;
    if (d) return hr ? `${d} d ${hr} h` : `${d} d`;
    if (hr) return m ? `${hr} h ${m} min` : `${hr} h`;
    return `${m} min`;
  }

  let toastTimer = 0;
  function toast(message, tone = "") {
    clearTimeout(toastTimer);
    toastEl.className = `toast ${tone}`;
    toastEl.textContent = message;
    toastTimer = setTimeout(() => toastEl.classList.add("hide"), 5000);
  }

  const dialog = document.getElementById("confirm");
  function confirmDialog({ title, body, confirm }) {
    document.getElementById("confirm-title").textContent = title;
    document.getElementById("confirm-body").textContent = body;
    document.getElementById("confirm-ok").textContent = confirm;
    dialog.returnValue = "";
    dialog.showModal();
    return new Promise((resolve) => {
      dialog.addEventListener("close", () => resolve(dialog.returnValue === "ok"), { once: true });
    });
  }
  document.getElementById("confirm-ok").addEventListener("click", () => dialog.close("ok"));
  document.getElementById("confirm-cancel").addEventListener("click", () => dialog.close("cancel"));

  const cautionIcon = () =>
    s(
      "svg",
      { viewBox: "0 0 20 20", "aria-hidden": "true" },
      s("circle", { cx: 10, cy: 10, r: 8 }),
      s("path", { d: "M10 6v5M10 14v.01" }),
    );
  const caution = (text) => h("p", { class: "caution" }, cautionIcon(), h("span", { text }));

  const pageHead = (title, lede, extra) =>
    h(
      "div",
      { class: "page-head" },
      h(
        "div",
        null,
        h("h1", { tabindex: "-1", text: title }),
        lede && h("p", { class: "lede", text: lede }),
      ),
      extra,
    );

  const stateBox = (title, body, kind = "", action) =>
    h(
      "div",
      { class: `card state ${kind}`, role: kind === "error" ? "alert" : null },
      h("h2", { text: title }),
      h("p", { text: body }),
      action && h("div", { class: "actions" }, action),
    );

  function dataTable(caption, headers, rows) {
    return h(
      "div",
      { class: "table-wrap" },
      h(
        "table",
        null,
        h("caption", { class: "sr-only", text: caption }),
        h(
          "thead",
          null,
          h(
            "tr",
            null,
            headers.map((t, i) => h("th", { scope: "col", class: i ? "num" : null, text: t })),
          ),
        ),
        h(
          "tbody",
          null,
          rows.map((r) =>
            h(
              "tr",
              null,
              r.map((c, i) =>
                h(i ? "td" : "th", { scope: i ? null : "row", class: i ? "num" : null, text: c }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  function niceMax(v) {
    const raw = Math.max(1, v) / 4;
    const mag = 10 ** Math.floor(Math.log10(raw));
    const step = [1, 2, 2.5, 5, 10].map((f) => f * mag).find((x) => x >= raw);
    return Math.max(4, Math.ceil(step) * 4);
  }

  /**
   * Time-series chart over `days`. Each series is { label, values, mark: "line" | "area" | "bar", cls }.
   * The chart is one keyboard stop: arrow keys move a cursor, and the readout below announces the day.
   */
  function timeChart({ title, days, series }) {
    const H = 220;
    const m = { t: 12, r: 12, b: 28, l: 40 };
    const ih = H - m.t - m.b;
    const n = days.length;
    const max = niceMax(Math.max(0, ...series.flatMap((x) => x.values)));
    const isBar = series.some((x) => x.mark === "bar");
    let W = 640;
    const iw = () => W - m.l - m.r;
    const slot = () => iw() / Math.max(n, 1);
    const x = (i) =>
      isBar ? m.l + (i + 0.5) * slot() : m.l + (n <= 1 ? iw() / 2 : (i * iw()) / (n - 1));
    const y = (v) => m.t + ih - (v / max) * ih;

    const axis = s("g", { class: "axis" });
    const marks = s("g");
    const cursorLine = s("line", { y1: m.t, y2: m.t + ih });
    const dots = series
      .filter((x) => x.mark !== "bar")
      .map((sr) => s("circle", { r: 4.5, class: sr.cls || null }));
    const cursor = s("g", { class: "cursor", visibility: "hidden" }, cursorLine, dots);
    const latest = series.map((sr) => `${sr.label} ${fmtNum(sr.values.at(-1))}`).join(", ");
    const svg = s(
      "svg",
      {
        role: "img",
        "aria-label": `${title}, ${n} days ending ${n ? fmtDay(days[n - 1]) : ""}. Latest: ${latest}.`,
      },
      axis,
      marks,
      cursor,
    );

    const draw = () => {
      svg.setAttribute("viewBox", `0 0 ${W} ${H}`);
      axis.replaceChildren();
      marks.replaceChildren();
      for (let k = 0; k <= 4; k++) {
        const v = (max / 4) * k;
        axis.append(
          s("line", { x1: m.l, x2: W - m.r, y1: y(v), y2: y(v), class: k ? null : "base" }),
          s("text", { x: m.l - 8, y: y(v) + 4, "text-anchor": "end", text: fmtNum(v) }),
        );
      }
      for (const i of [...new Set([0, Math.floor((n - 1) / 2), n - 1])].filter((i) => i >= 0)) {
        const anchor = i === 0 && !isBar ? "start" : i === n - 1 && !isBar ? "end" : "middle";
        axis.append(s("text", { x: x(i), y: H - 6, "text-anchor": anchor, text: fmtDay(days[i]) }));
      }
      for (const sr of series) {
        if (sr.mark === "bar") {
          const bw = Math.max(2, slot() * 0.62);
          sr.bars = sr.values.map((v, i) =>
            s("rect", {
              class: "mark-bar",
              x: x(i) - bw / 2,
              y: y(v),
              width: bw,
              height: Math.max(0, m.t + ih - y(v)),
              rx: Math.min(3, bw / 3),
            }),
          );
          marks.append(...sr.bars);
          continue;
        }
        const pts = sr.values.map((v, i) => `${x(i).toFixed(1)},${y(v).toFixed(1)}`);
        if (sr.mark === "area" && n > 1)
          marks.append(
            s("path", {
              class: "mark-area",
              d: `M${x(0)},${y(0)}L${pts.join("L")}L${x(n - 1)},${y(0)}Z`,
            }),
          );
        marks.append(s("path", { class: `mark-line ${sr.cls || ""}`, d: `M${pts.join("L")}` }));
      }
      if (active >= 0 && cursor.getAttribute("visibility") === "visible") show(active);
    };

    const readout = h("p", {
      class: "readout",
      "aria-live": "polite",
      text: "Hover or focus the chart, then use the arrow keys.",
    });

    let active = -1;
    const show = (i) => {
      if (!n) return;
      active = Math.max(0, Math.min(n - 1, i));
      cursor.setAttribute("visibility", "visible");
      cursorLine.setAttribute("x1", x(active));
      cursorLine.setAttribute("x2", x(active));
      let d = 0;
      for (const sr of series) {
        if (sr.mark === "bar") sr.bars.forEach((b, j) => b.classList.toggle("on", j === active));
        else {
          dots[d].setAttribute("cx", x(active));
          dots[d++].setAttribute("cy", y(sr.values[active]));
        }
      }
      readout.textContent = `${fmtDay(days[active])}: ${series.map((sr) => `${sr.label} ${fmtNum(sr.values[active])}`).join(" · ")}`;
    };
    const hide = () => {
      cursor.setAttribute("visibility", "hidden");
      for (const sr of series) if (sr.bars) sr.bars.forEach((b) => b.classList.remove("on"));
    };

    const box = h("div", {
      class: "chart",
      tabindex: "0",
      role: "group",
      "aria-label": `${title}. Use left and right arrow keys to read each day.`,
      onpointermove: (e) => {
        const r = svg.getBoundingClientRect();
        const px = ((e.clientX - r.left) / r.width) * W;
        show(isBar ? Math.floor((px - m.l) / slot()) : Math.round(((px - m.l) / iw()) * (n - 1)));
      },
      onpointerleave: () => document.activeElement !== box && hide(),
      onfocus: () => show(active < 0 ? n - 1 : active),
      onblur: hide,
      onkeydown: (e) => {
        const step = { ArrowLeft: -1, ArrowRight: 1, Home: -Infinity, End: Infinity }[e.key];
        if (step === undefined) return;
        e.preventDefault();
        show(Number.isFinite(step) ? active + step : step < 0 ? 0 : n - 1);
      },
    });
    box.append(svg);
    draw();
    // Redraw at the box's real pixel width so axis text stays 12px instead of scaling with the viewBox.
    new ResizeObserver(([entry]) => {
      const w = Math.round(entry.contentRect.width);
      if (w > 0 && w !== W) {
        W = Math.max(240, w);
        draw();
      }
    }).observe(box);

    const table = dataTable(
      title,
      ["Day", ...series.map((x) => x.label)],
      days.map((d, i) => [fmtDay(d), ...series.map((x) => fmtNum(x.values[i]))]),
    );
    return [
      box,
      readout,
      h("details", { class: "data" }, h("summary", { text: "Show as table" }), table),
    ];
  }

  /** A share drawn on a fixed 0–100% scale: the dot is the estimate, the whisker its 95% interval. */
  function whisker(share, { axis = false } = {}) {
    const W = 280;
    const H = axis ? 32 : 18;
    const cy = 9;
    const px = (v) => 6 + v * (W - 12);
    const label =
      share.share == null
        ? "No data yet"
        : `${fmtPct(share.share)}, 95% interval ${fmtInterval(share.interval)}, ${share.count} of ${share.of}`;
    const g = s(
      "svg",
      { class: "whisker wk", viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": label },
      s("title", { text: label }),
    );
    g.append(s("line", { class: "track", x1: px(0), x2: px(1), y1: cy, y2: cy }));
    for (const t of [0, 0.25, 0.5, 0.75, 1]) {
      g.append(s("line", { class: "tick", x1: px(t), x2: px(t), y1: cy - 3, y2: cy + 3 }));
      if (axis && t % 0.5 === 0)
        g.append(
          s("text", {
            x: px(t),
            y: H - 2,
            "text-anchor": t === 0 ? "start" : t === 1 ? "end" : "middle",
            text: `${t * 100}%`,
          }),
        );
    }
    if (share.interval) {
      const lo = px(share.interval.low);
      const hi = px(share.interval.high);
      g.append(
        s("rect", {
          class: "ci-band",
          x: lo,
          y: cy - 5,
          width: Math.max(0, hi - lo),
          height: 10,
          rx: 5,
        }),
        s("path", {
          class: "ci",
          d: `M${lo},${cy}H${hi}M${lo},${cy - 5}V${cy + 5}M${hi},${cy - 5}V${cy + 5}`,
        }),
      );
    }
    if (share.share != null) g.append(s("circle", { class: "pt", cx: px(share.share), cy, r: 5 }));
    return g;
  }

  const shareText = (sh) =>
    h(
      "span",
      { class: "share-text" },
      h("b", { text: fmtPct(sh.share) }),
      " ",
      h("span", {
        text: sh.interval
          ? `(${fmtInterval(sh.interval)}) · ${sh.count}/${sh.of}`
          : `${sh.count}/${sh.of}`,
      }),
    );

  function kpi(label, value, sub, { lead = false, share } = {}) {
    return h(
      "div",
      { class: `card kpi${lead ? " lead" : ""}` },
      h("p", { class: "kpi-label", text: label }),
      h("p", { class: "kpi-value", text: value }),
      sub && h("p", { class: "kpi-sub", text: sub }),
      share && whisker(share),
    );
  }

  const shareSub = (sh, noun) =>
    sh.of
      ? `95% CI ${fmtInterval(sh.interval)} · ${sh.count} of ${sh.of} ${noun}`
      : `No eligible ${noun} yet`;

  async function renderOverview() {
    const o = await api("/overview");
    const daily = o.daily || [];
    const last = daily.find((d) => d.day === o.today) || daily.at(-1) || { dau: null, wau: null };
    const sum = (k) => daily.reduce((a, d) => a + (d[k] || 0), 0);
    const ret = (n) => (o.retention || []).find((r) => r.day === n);
    const days = daily.map((d) => d.day);
    const period = days.length ? `${fmtDay(days[0])} – ${fmtDay(days.at(-1))}` : "No days yet";

    const kpis = h(
      "div",
      { class: "grid kpis" },
      kpi("Daily active today", fmtNum(last.dau), `${fmtNum(last.wau)} active this week`, {
        lead: true,
      }),
      kpi("Weekly active", fmtNum(last.wau), "Rolling 7 days"),
      kpi("Pairs created", fmtNum(sum("pairsCreated")), `In the last ${days.length} days`),
      kpi(
        "Pair completion",
        fmtPct(o.pairCompletion.share),
        shareSub(o.pairCompletion, "invites"),
        { share: o.pairCompletion },
      ),
      kpi(
        "Notes per pair per day",
        o.notesPerPairPerDay.mean == null ? "—" : o.notesPerPairPerDay.mean.toFixed(2),
        `Across ${fmtNum(o.notesPerPairPerDay.pairs)} pairs`,
      ),
      [1, 7].map((n) => {
        const r = ret(n);
        if (!r) return kpi(`D${n} retention`, "—", "Not computed yet");
        return kpi(
          `D${n} retention, both active`,
          fmtPct(r.bothActive.share),
          shareSub(r.bothActive, "pairs"),
          { share: r.bothActive },
        );
      }),
    );

    const totals = h(
      "p",
      { class: "totals" },
      ["users", "pairs", "notes"].map((k) =>
        h("span", null, h("b", { text: fmtNum(o.totals[k]) }), ` ${k} all time`),
      ),
    );

    const chartCard = (title, sub, legend, series, wide) =>
      h(
        "section",
        { class: `card${wide ? " wide" : ""}`, "aria-label": title },
        h(
          "div",
          { class: "chart-head" },
          h(
            "div",
            null,
            h("h3", { class: "card-title", text: title }),
            h("p", { class: "card-sub", text: sub }),
          ),
          legend,
        ),
        timeChart({ title, days, series }),
      );

    const charts = daily.length
      ? h(
          "div",
          { class: "grid charts" },
          chartCard(
            "Active people",
            "Daily and weekly active, per day",
            h(
              "p",
              { class: "legend", "aria-hidden": "true" },
              h("span", { text: "DAU" }),
              h("span", { class: "s2", text: "WAU" }),
            ),
            [
              { label: "DAU", values: daily.map((d) => d.dau), mark: "area" },
              { label: "WAU", values: daily.map((d) => d.wau), mark: "line", cls: "s2" },
            ],
            true,
          ),
          chartCard("Pairs created", "New pairs per day", null, [
            { label: "Pairs", values: daily.map((d) => d.pairsCreated), mark: "bar" },
          ]),
          chartCard("Notes sent", "Notes per day, all pairs", null, [
            { label: "Notes", values: daily.map((d) => d.notes), mark: "bar" },
          ]),
        )
      : stateBox("No daily data yet", "Charts appear once the first day of events is recorded.");

    return [
      pageHead("Overview", `${period} · today is ${fmtDay(o.today)}`, totals),
      kpis,
      caution(
        "Small numbers: with a few dozen pairs one couple can move a rate by several points. Read the 95% range, not just the dot.",
      ),
      h("div", { class: "section" }, h("h2", { class: "section-title", text: "Activity" }), charts),
      h(
        "section",
        { class: "section" },
        h("h2", { class: "section-title", text: "Funnel" }),
        h("div", { class: "card" }, funnel(o.funnel || [])),
      ),
    ];
  }

  function funnel(steps) {
    const base = steps.find((x) => x.count != null);
    if (!base) return h("p", { class: "card-sub", text: "No funnel data yet." });
    return h(
      "ol",
      { class: "funnel" },
      steps.map((st) => {
        const known = st.count != null;
        const frac = known && base.count ? st.count / base.count : 0;
        return h(
          "li",
          null,
          h("span", { class: "f-label", text: st.label }),
          h(
            "span",
            { class: "f-track", "aria-hidden": "true" },
            known &&
              h("span", { class: "f-fill", style: { "--w": `${(frac * 100).toFixed(1)}%` } }),
          ),
          h(
            "span",
            { class: "f-value" },
            h("b", { text: known ? fmtNum(st.count) : "—" }),
            known && st !== base ? ` · ${fmtPct(frac, 0)} of ${base.label.toLowerCase()}` : "",
          ),
          st.note && h("span", { class: "f-note", text: st.note }),
        );
      }),
    );
  }

  const statusChips = (item) =>
    h(
      "span",
      { class: "chips" },
      h("span", { class: `chip ${item.config.status}`, text: item.config.status }),
      item.config.killed && h("span", { class: "chip killed", text: "KILLED" }),
    );

  const splitText = (weights) => {
    const total = Object.values(weights).reduce((a, b) => a + b, 0);
    return Object.entries(weights)
      .map(([v, w]) => `${v} ${total ? fmtPct(w / total, 0) : "0%"}`)
      .join(", ");
  };

  const changedText = (item) =>
    item.version
      ? `v${item.version} · ${item.updatedBy || "unknown"} · ${fmtWhen(item.updatedAt)}`
      : "Never edited";

  const DONE = { start: "started", stop: "stopped", kill: "killed", unkill: "unkilled" };

  async function runAction(item, action) {
    if (action === "kill") {
      const ok = await confirmDialog({
        title: `Kill ${item.key}?`,
        body: "Every pair gets the default variant right away, whatever they were assigned. You can unkill it later.",
        confirm: "Kill experiment",
      });
      if (!ok) return;
    }
    try {
      await api(`/experiments/${enc(item.key)}/${action}`, {
        method: "POST",
        body: { expectedVersion: item.version },
      });
      toast(`${item.key}: ${DONE[action]}.`);
    } catch (err) {
      if (err.status === 409)
        toast(
          `Someone else changed ${item.key}. Showing the latest; check it and try again.`,
          "warn",
        );
      else return toast(errorText(err), "bad");
    }
    route();
  }

  function experimentCard(item) {
    const c = item.config;
    const valid = [];
    if (c.status === "draft" || c.status === "stopped") valid.push(["start", "Start", "primary"]);
    if (c.status === "running") valid.push(["stop", "Stop", ""]);
    valid.push(c.killed ? ["unkill", "Unkill", "quiet"] : ["kill", "Kill", "danger"]);

    const actions = h(
      "div",
      { class: "actions" },
      valid.map(([a, label, cls]) =>
        h("button", {
          type: "button",
          class: `btn ${cls}`,
          text: label,
          "aria-label": `${label} ${item.key}`,
          onclick: async (e) => {
            const btn = e.currentTarget;
            btn.disabled = true;
            await runAction(item, a);
            btn.disabled = false;
          },
        }),
      ),
    );

    const r = item.results;
    let results;
    if (!r || !r.variants.length)
      results = h("p", {
        class: "card-sub results",
        text: "No results yet. They appear once pairs are assigned.",
      });
    else {
      results = h(
        "div",
        { class: "results" },
        h(
          "div",
          { class: "table-wrap" },
          h(
            "table",
            { class: "stacked" },
            h("caption", { class: "sr-only", text: `${item.key} results by variant` }),
            h(
              "thead",
              null,
              h(
                "tr",
                null,
                h("th", { scope: "col", text: "Variant" }),
                h("th", { scope: "col", class: "num", text: "Pairs" }),
                h("th", { scope: "col", text: "North star, 95% interval (0–100%)" }),
                h("th", { scope: "col", class: "num", text: "Median to first note" }),
              ),
            ),
            h(
              "tbody",
              null,
              r.variants.map((v) =>
                h(
                  "tr",
                  null,
                  h("td", { class: "lead-cell mono", "data-label": "Variant", text: v.variant }),
                  h("td", { class: "num", "data-label": "Pairs", text: fmtNum(v.pairs) }),
                  h(
                    "td",
                    { "data-label": "North star" },
                    h(
                      "div",
                      { class: "share" },
                      shareText(v.northStar),
                      whisker(v.northStar, { axis: true }),
                    ),
                  ),
                  h("td", {
                    class: "num",
                    "data-label": "Median to first note",
                    text: fmtDuration(v.medianToFirstNote),
                  }),
                ),
              ),
            ),
          ),
        ),
        r.caution && caution(r.caution),
      );
    }

    return h(
      "article",
      { class: "card", "aria-labelledby": `exp-${item.key}` },
      h(
        "div",
        { class: "exp-head" },
        h(
          "div",
          { class: "exp-title" },
          h("h2", { id: `exp-${item.key}`, text: item.key }),
          statusChips(item),
        ),
        actions,
      ),
      c.description && h("p", { class: "desc", text: c.description }),
      h(
        "p",
        { class: "meta" },
        h("span", null, "Exposure ", h("b", { text: `${fmtNum(c.exposure)}%` })),
        h("span", null, "Split ", h("b", { text: splitText(c.weights) })),
        h("span", null, "Default ", h("b", { class: "mono", text: c.default })),
        h("span", { text: changedText(item) }),
      ),
      results,
    );
  }

  async function renderExperiments() {
    const { items } = await api("/experiments");
    const exps = items.filter((i) => i.kind === "experiment");
    const head = pageHead("Experiments", "Assignment is per pair. Flags live on the Flags page.");
    if (!exps.length)
      return [
        head,
        stateBox("No experiments yet", "Experiments defined in code show up here once deployed."),
      ];
    return [head, h("div", { class: "stack" }, exps.map(experimentCard))];
  }

  function flatten(obj, prefix = "", out = {}) {
    if (obj == null || typeof obj !== "object" || Array.isArray(obj)) {
      if (prefix) out[prefix] = obj;
      return out;
    }
    for (const [k, v] of Object.entries(obj)) flatten(v, prefix ? `${prefix}.${k}` : k, out);
    return out;
  }

  const showValue = (v) =>
    v === undefined || v === null ? "none" : Array.isArray(v) ? v.join(", ") || "none" : String(v);

  function diffList(before, after) {
    const a = flatten(before || {});
    const b = flatten(after || {});
    const keys = [...new Set([...Object.keys(a), ...Object.keys(b)])].filter(
      (k) => JSON.stringify(a[k]) !== JSON.stringify(b[k]),
    );
    if (!keys.length) return null;
    return h(
      "ul",
      { class: "diff" },
      keys.map((k) =>
        h(
          "li",
          null,
          h("code", { text: k }),
          " ",
          h("span", { class: "was", text: showValue(a[k]) }),
          " → ",
          h("span", { class: "now", text: showValue(b[k]) }),
        ),
      ),
    );
  }

  function historyList(changes, { showKey }) {
    if (!changes.length) return h("p", { class: "card-sub", text: "No changes recorded yet." });
    return h(
      "ol",
      { class: "history" },
      changes.map((c) =>
        h(
          "li",
          null,
          h(
            "p",
            { class: "h-line" },
            h("time", { datetime: new Date(c.at).toISOString(), text: fmtWhen(c.at) }),
            h("span", { class: "chip", text: c.action }),
            showKey && h("a", { class: "mono", href: `#/flags/${enc(c.key)}`, text: c.key }),
            h("span", { class: "who", text: c.by }),
            c.pairId && h("span", { class: "mono", text: `pair ${c.pairId}` }),
          ),
          diffList(c.before, c.after),
        ),
      ),
    );
  }

  async function renderFlags([key]) {
    if (key) return renderFlagEditor(key);
    const [{ items }, { changes }] = await Promise.all([api("/flags"), api("/history?limit=50")]);
    const head = pageHead("Flags", "Every experiment and flag. Open one to edit its config.");
    if (!items.length)
      return [
        head,
        stateBox(
          "Nothing defined yet",
          "Flags and experiments appear here once the backend declares them.",
        ),
      ];
    const table = h(
      "div",
      { class: "card" },
      h(
        "div",
        { class: "table-wrap" },
        h(
          "table",
          { class: "stacked" },
          h("caption", { class: "sr-only", text: "All flags and experiments" }),
          h(
            "thead",
            null,
            h(
              "tr",
              null,
              ["Key", "Kind", "Status", "Version", "Last changed"].map((t) =>
                h("th", { scope: "col", text: t }),
              ),
            ),
          ),
          h(
            "tbody",
            null,
            items.map((it) =>
              h(
                "tr",
                null,
                h(
                  "td",
                  { class: "lead-cell", "data-label": "Key" },
                  h("a", { class: "mono", href: `#/flags/${enc(it.key)}`, text: it.key }),
                ),
                h("td", { "data-label": "Kind", text: it.kind }),
                h("td", { "data-label": "Status" }, statusChips(it)),
                h("td", { "data-label": "Version", text: it.version ? `v${it.version}` : "—" }),
                h("td", {
                  "data-label": "Last changed",
                  text: it.version
                    ? `${it.updatedBy || "unknown"}, ${fmtWhen(it.updatedAt)}`
                    : "Never edited",
                }),
              ),
            ),
          ),
        ),
      ),
    );
    return [
      head,
      table,
      h(
        "section",
        { class: "section" },
        h("h2", { class: "section-title", text: "Recent changes" }),
        h("div", { class: "card" }, historyList(changes, { showKey: true })),
      ),
    ];
  }

  const VERSION_PATTERN = "^\\d{1,4}(\\.\\d{1,4}){0,3}(\\+\\d{1,8})?$";
  let fieldSeq = 0;
  const fid = () => `f${++fieldSeq}`;

  function field(labelText, control, hint, target = control) {
    const id = target.id || (target.id = fid());
    const hintEl = hint && h("p", { class: "hint", id: `${id}-hint`, text: hint });
    if (hintEl) target.setAttribute("aria-describedby", hintEl.id);
    return h("div", { class: "field" }, h("label", { for: id, text: labelText }), control, hintEl);
  }

  async function renderFlagEditor(key) {
    const [{ items }, { changes }] = await Promise.all([
      api("/flags"),
      api(`/history?key=${enc(key)}&limit=50`),
    ]);
    const back = h("a", { class: "back", href: "#/flags", text: "← All flags" });
    const item = items.find((i) => i.key === key);
    if (!item)
      return [
        back,
        pageHead(key),
        stateBox("No such flag", "It may have been removed from the code. Pick one from the list."),
      ];
    const c = item.config;
    const t = c.targeting || {};

    const desc = h("textarea", { rows: "3", text: c.description || "" });
    const weightInputs = new Map();
    const outputs = new Map();
    const updateSplit = () => {
      const vals = [...weightInputs.values()].map((i) =>
        Number.isFinite(i.valueAsNumber) ? Math.max(0, i.valueAsNumber) : 0,
      );
      const total = vals.reduce((a, b) => a + b, 0);
      [...outputs.values()].forEach(
        (o, i) => (o.textContent = total ? fmtPct(vals[i] / total, 0) : "0%"),
      );
    };
    const weightRows = item.variants.map((v) => {
      const id = fid();
      const input = h("input", {
        id,
        type: "number",
        min: "0",
        step: "any",
        required: true,
        inputmode: "decimal",
        value: String(c.weights[v] ?? 0),
        oninput: updateSplit,
      });
      const out = h("output", { for: id, "aria-label": `${v} share` });
      weightInputs.set(v, input);
      outputs.set(v, out);
      return h("div", { class: "weight" }, h("label", { for: id, text: v }), input, out);
    });
    updateSplit();

    const def = h(
      "select",
      null,
      item.variants.map((v) => h("option", { value: v, text: v, selected: v === c.default })),
    );
    const exposure = h("input", {
      type: "number",
      min: "0",
      max: "100",
      step: "any",
      required: true,
      value: String(c.exposure),
    });
    const status = h(
      "select",
      null,
      ["draft", "running", "stopped"].map((v) =>
        h("option", { value: v, text: v, selected: v === c.status }),
      ),
    );
    const killed = h("input", { type: "checkbox", checked: c.killed });
    const minV = h("input", {
      type: "text",
      pattern: VERSION_PATTERN,
      placeholder: "e.g. 1.4",
      value: t.minAppVersion || "",
      autocomplete: "off",
      spellcheck: "false",
    });
    const maxV = h("input", {
      type: "text",
      pattern: VERSION_PATTERN,
      placeholder: "e.g. 2.0+120",
      value: t.maxAppVersion || "",
      autocomplete: "off",
      spellcheck: "false",
    });
    const bands = ["13-17", "18+"].map((b) => [
      b,
      h("input", { type: "checkbox", checked: (t.ageBands || []).includes(b) }),
    ]);
    const pairIds = h("textarea", {
      class: "mono",
      rows: "4",
      spellcheck: "false",
      text: (t.pairIds || []).join("\n"),
    });
    const msg = h("div", { class: "form-msg", role: "alert" });
    const save = h("button", { type: "submit", class: "btn primary", text: "Save changes" });

    const readConfig = () => {
      const targeting = {};
      if (minV.value.trim()) targeting.minAppVersion = minV.value.trim();
      if (maxV.value.trim()) targeting.maxAppVersion = maxV.value.trim();
      const ageBands = bands.filter(([, el]) => el.checked).map(([b]) => b);
      if (ageBands.length) targeting.ageBands = ageBands;
      const ids = pairIds.value
        .split(/\r?\n/)
        .map((x) => x.trim())
        .filter(Boolean);
      if (ids.length) targeting.pairIds = ids;
      return {
        description: desc.value.trim(),
        weights: Object.fromEntries([...weightInputs].map(([v, i]) => [v, i.valueAsNumber])),
        default: def.value,
        exposure: exposure.valueAsNumber,
        status: status.value,
        killed: killed.checked,
        targeting,
      };
    };

    const form = h(
      "form",
      {
        class: "card",
        novalidate: true,
        "aria-label": `Edit ${key}`,
        onsubmit: async (e) => {
          e.preventDefault();
          msg.replaceChildren();
          if (!form.reportValidity()) return;
          save.disabled = true;
          try {
            await api(`/flags/${enc(key)}`, {
              method: "PUT",
              body: { config: readConfig(), expectedVersion: item.version },
            });
            toast(`Saved ${key}.`);
            route();
          } catch (err) {
            save.disabled = false;
            if (err.status === 409) {
              msg.append(
                h("p", {
                  text: `Someone else changed ${key} while you were editing (now v${err.body?.current ?? "?"}). Load the latest, then re-apply your edits.`,
                }),
                h(
                  "div",
                  { class: "actions" },
                  h("button", {
                    type: "button",
                    class: "btn",
                    text: "Load latest",
                    onclick: () => route(),
                  }),
                ),
              );
            } else if (err.status === 400)
              msg.textContent = err.body?.message || "The server rejected this config.";
            else msg.textContent = errorText(err);
            msg.focus?.();
          }
        },
      },
      h("fieldset", null, h("legend", { text: "About" }), field("Description", desc)),
      h(
        "fieldset",
        null,
        h("legend", { text: "Variants" }),
        h("p", {
          class: "label",
          id: `${key}-w`,
          text: "Weight per variant, with the resulting split",
        }),
        h("div", { class: "weights", role: "group", "aria-labelledby": `${key}-w` }, weightRows),
        field("Default variant", def, "Served when killed, outside exposure or not targeted."),
      ),
      h(
        "fieldset",
        null,
        h("legend", { text: "Rollout" }),
        h(
          "div",
          { class: "row" },
          field(
            "Exposure",
            h("div", { class: "suffix" }, exposure, "%"),
            "Share of eligible pairs that enter.",
            exposure,
          ),
          field("Status", status),
        ),
        h("label", { class: "check" }, killed, "Killed: everyone gets the default"),
      ),
      h(
        "fieldset",
        null,
        h("legend", { text: "Targeting" }),
        h("div", { class: "row" }, field("Min app version", minV), field("Max app version", maxV)),
        h("p", { class: "hint", text: "Like 1.4 or 2.0.1+120. Blank means no limit." }),
        h(
          "fieldset",
          { class: "field" },
          h("legend", { class: "label", text: "Age bands" }),
          bands.map(([b, el]) => h("label", { class: "check" }, el, b)),
          h("p", {
            class: "hint",
            text: "None checked means everyone. The server doesn't know age bands yet, so checking one excludes everyone for now.",
          }),
        ),
        field("Pair ids", pairIds, "One per line. Blank means all pairs."),
      ),
      msg,
      h(
        "div",
        { class: "form-foot" },
        save,
        h("button", {
          type: "button",
          class: "btn quiet",
          text: "Discard edits",
          onclick: () => route(),
        }),
        h("p", { class: "hint", text: changedText(item) }),
      ),
    );
    msg.setAttribute("tabindex", "-1");

    return [
      back,
      pageHead(key, `${item.kind} · ${item.variants.length} variants`, statusChips(item)),
      h(
        "div",
        { class: "grid split" },
        form,
        h(
          "section",
          { class: "card", "aria-labelledby": "hist-title" },
          h("h2", { class: "card-title", id: "hist-title", text: "History" }),
          historyList(changes, { showKey: false }),
        ),
      ),
    ];
  }

  const REASONS = {
    killed: "Killed, so everyone gets the default",
    override: "An admin override is set",
    draft: "Still a draft, not started",
    stored: "Kept from its stored assignment",
    "stored-retired": "Stored variant was retired",
    stopped: "Stopped, no new assignments",
    "not-targeted": "Outside the targeting rules",
    entered: "Newly entered the experiment",
    "outside-exposure": "Outside the exposure percentage",
  };

  async function overrideAction(pairId, key, variant) {
    try {
      if (variant)
        await api(`/pairs/${enc(pairId)}/overrides/${enc(key)}`, {
          method: "PUT",
          body: { variant },
        });
      else await api(`/pairs/${enc(pairId)}/overrides/${enc(key)}`, { method: "DELETE" });
      toast(variant ? `Override set: ${key} → ${variant}.` : `Override cleared for ${key}.`);
      route();
    } catch (err) {
      toast(errorText(err), "bad");
    }
  }

  async function renderPairs([pairId]) {
    const input = h("input", {
      type: "search",
      name: "pair",
      value: pairId || "",
      required: true,
      autocomplete: "off",
      spellcheck: "false",
      placeholder: "Pair id",
      "aria-label": "Pair id",
    });
    const lookup = h(
      "form",
      {
        class: "lookup",
        role: "search",
        onsubmit: (e) => {
          e.preventDefault();
          const id = input.value.trim();
          if (id) location.hash = `#/pairs/${enc(id)}`;
        },
      },
      input,
      h("button", { type: "submit", class: "btn primary", text: "Look up" }),
    );
    const head = pageHead("Pairs", "Look up one pair by its id. There is no search by person.");
    if (!pairId)
      return [
        head,
        lookup,
        h(
          "div",
          { class: "section" },
          stateBox(
            "Enter a pair id",
            "You'll see its assignments, overrides, the decision for every flag, and event counts.",
          ),
        ),
      ];

    let pair;
    let flags;
    try {
      [pair, { items: flags }] = await Promise.all([api(`/pairs/${enc(pairId)}`), api("/flags")]);
    } catch (err) {
      if (err.status !== 404) throw err;
      return [
        head,
        lookup,
        h(
          "div",
          { class: "section" },
          stateBox("No pair with that id", "Check the id and try again. Ids are case-sensitive."),
        ),
      ];
    }

    const byKey = new Map(flags.map((f) => [f.key, f]));
    const assigned = new Map(pair.assignments.map((a) => [a.key, a]));
    const overrides = new Map(pair.overrides.map((o) => [o.key, o]));
    const decisions = new Map(pair.decisions.map((d) => [d.key, d]));
    const keys = [
      ...new Set([...byKey.keys(), ...decisions.keys(), ...assigned.keys(), ...overrides.keys()]),
    ];

    const rows = keys.map((key) => {
      const d = decisions.get(key);
      const a = assigned.get(key);
      const o = overrides.get(key);
      const f = byKey.get(key);
      let control = h("span", { class: "card-sub", text: "Not in the flag list" });
      if (f) {
        const sel = h(
          "select",
          { "aria-label": `Override variant for ${key}` },
          f.variants.map((v) =>
            h("option", {
              value: v,
              text: v,
              selected: o ? v === o.variant : v === f.config.default,
            }),
          ),
        );
        control = h(
          "div",
          { class: "override" },
          sel,
          h("button", {
            type: "button",
            class: "btn",
            text: "Set",
            "aria-label": `Set override for ${key}`,
            onclick: () => overrideAction(pair.pairId, key, sel.value),
          }),
          o &&
            h("button", {
              type: "button",
              class: "btn quiet",
              text: "Clear",
              "aria-label": `Clear override for ${key}`,
              onclick: () => overrideAction(pair.pairId, key, null),
            }),
        );
      }
      return h(
        "tr",
        null,
        h("td", { class: "lead-cell mono", "data-label": "Key", text: key }),
        h(
          "td",
          { "data-label": "Gets" },
          h(
            "div",
            { class: "decision" },
            d && d.variant != null
              ? h("b", { class: "mono", text: d.variant })
              : h("span", { class: "not-listed", text: "not listed" }),
            d && h("span", { class: "why", text: REASONS[d.reason] || d.reason }),
          ),
        ),
        h("td", {
          "data-label": "Stored",
          text: a ? `${a.variant}, ${fmtWhen(a.assignedAt)}` : "—",
        }),
        h("td", {
          "data-label": "Override",
          text: o ? `${o.variant} by ${o.setBy}, ${fmtWhen(o.setAt)}` : "—",
        }),
        h("td", { "data-label": "Change" }, control),
      );
    });

    const events = [...pair.events].sort((a, b) => b.count - a.count);
    return [
      head,
      lookup,
      h(
        "section",
        { class: "section card", "aria-label": "Pair" },
        h(
          "dl",
          { class: "facts" },
          h(
            "div",
            null,
            h("dt", { text: "Pair hash" }),
            h("dd", { class: "mono", text: pair.pairHash }),
          ),
          h("div", null, h("dt", { text: "Members" }), h("dd", { text: fmtNum(pair.members) })),
          h(
            "div",
            null,
            h("dt", { text: "Paired" }),
            h("dd", { text: pair.pairedAt ? fmtWhen(pair.pairedAt) : "Not yet" }),
          ),
        ),
      ),
      h(
        "section",
        { class: "section" },
        h("h2", { class: "section-title", text: "Flags and experiments for this pair" }),
        h(
          "div",
          { class: "card" },
          keys.length
            ? h(
                "div",
                { class: "table-wrap" },
                h(
                  "table",
                  { class: "stacked" },
                  h("caption", { class: "sr-only", text: "Decisions, assignments and overrides" }),
                  h(
                    "thead",
                    null,
                    h(
                      "tr",
                      null,
                      ["Key", "Gets", "Stored", "Override", "Change"].map((t) =>
                        h("th", { scope: "col", text: t }),
                      ),
                    ),
                  ),
                  h("tbody", null, rows),
                ),
              )
            : h("p", { class: "card-sub", text: "No flags defined." }),
        ),
      ),
      h(
        "section",
        { class: "section" },
        h("h2", { class: "section-title", text: "Events" }),
        h(
          "div",
          { class: "card" },
          events.length
            ? h(
                "ul",
                { class: "events" },
                events.map((e) =>
                  h(
                    "li",
                    null,
                    h("span", { class: "mono", text: e.name }),
                    h("b", { text: fmtNum(e.count) }),
                  ),
                ),
              )
            : h("p", { class: "card-sub", text: "No events recorded for this pair." }),
        ),
      ),
    ];
  }

  const ROUTES = {
    overview: renderOverview,
    experiments: renderExperiments,
    flags: renderFlags,
    pairs: renderPairs,
  };
  let renderSeq = 0;
  let firstRender = true;

  async function route() {
    const parts = location.hash.replace(/^#\/?/, "").split("/");
    const name = ROUTES[parts[0]] ? parts[0] : "overview";
    const args = parts.slice(1).map((p) => {
      try {
        return decodeURIComponent(p);
      } catch {
        return p;
      }
    });
    for (const a of document.querySelectorAll(".nav a")) {
      if (a.dataset.route === name) a.setAttribute("aria-current", "page");
      else a.removeAttribute("aria-current");
    }
    const seq = ++renderSeq;
    const busy = setTimeout(
      () =>
        seq === renderSeq &&
        main.replaceChildren(h("p", { class: "state loading", role: "status", text: "Loading…" })),
      120,
    );
    let nodes;
    try {
      nodes = await ROUTES[name](args);
    } catch (err) {
      nodes = [
        stateBox(
          err.status === 403 ? "Not authorised" : "Couldn't load this page",
          errorText(err),
          "error",
          h("button", { type: "button", class: "btn", text: "Try again", onclick: () => route() }),
        ),
      ];
      nodes[0].classList.add("section");
    }
    clearTimeout(busy);
    if (seq !== renderSeq) return;
    const wrap = h("div", { class: "enter" }, nodes);
    [...wrap.children].forEach((el, i) => el.style.setProperty("--i", String(Math.min(i, 6))));
    main.replaceChildren(wrap);
    document.title = `${main.querySelector("h1")?.textContent || "billet"} · billet admin`;
    if (!firstRender) main.querySelector("h1")?.focus({ preventScroll: false });
    firstRender = false;
  }

  document.getElementById("skip").addEventListener("click", (e) => {
    e.preventDefault();
    main.focus();
  });

  window.addEventListener("hashchange", route);
  api("/me").then(
    (me) => (document.getElementById("me-email").textContent = me.email),
    (err) =>
      (document.getElementById("me-email").textContent =
        err.status === 403
          ? "Not authorised through Cloudflare Access"
          : "Signed-in email unavailable"),
  );
  route();
})();
