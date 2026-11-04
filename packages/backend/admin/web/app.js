import {
  deltaOf,
  diffConfig,
  experimentActions,
  fmtDay,
  funnelSteps,
  matchesQuery,
  mergeAudit,
  niceMax,
  relativeTime,
  sortRows,
  sparkPath,
  splitShares,
  statePill,
} from "./lib.js";

const SVGNS = "http://www.w3.org/2000/svg";
const main = document.getElementById("main");
const toastEl = document.getElementById("toast");
const DOM_PROPS = new Set(["value", "checked", "selected", "disabled", "required", "open"]);

function setProps(el, props) {
  if (!props) return;
  for (const [k, v] of Object.entries(props)) {
    if (v == null || v === false) continue;
    if (k === "text") el.textContent = String(v);
    else if (k === "class") el.setAttribute("class", v);
    else if (k === "style") for (const [p, val] of Object.entries(v)) el.style.setProperty(p, val);
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
    if (err.status === 503)
      return "The server couldn't read its data (D1 may be down). Try again in a minute.";
    return err.message;
  }
  return "Something went wrong in the page. Reload and try again.";
}

const fmtNum = (n, digits = 2) =>
  n == null ? "—" : n.toLocaleString("en-US", { maximumFractionDigits: digits });
const fmtPct = (x, digits = 1) =>
  x == null ? "—" : `${(x * 100).toFixed(digits).replace(/\.0$/, "")}%`;
const fmtInterval = (i) => (i ? `${fmtPct(i.low, 0)}–${fmtPct(i.high, 0)}` : "no interval yet");
const timeFmt = new Intl.DateTimeFormat("en-US", { dateStyle: "medium", timeStyle: "short" });
const fmtWhen = (ms) => (ms == null ? "—" : timeFmt.format(ms));
const fmtInstant = (iso) => (iso ? fmtWhen(Date.parse(iso)) : "—");

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

/** A relative time with the exact one on hover and for screen readers; kept fresh by `tick`. */
const ago = (ms) =>
  ms == null
    ? h("span", { class: "sub", text: "never" })
    : h("time", {
        datetime: new Date(ms).toISOString(),
        title: fmtWhen(ms),
        "data-at": String(ms),
        text: relativeTime(ms, Date.now()),
      });

function tick() {
  for (const el of document.querySelectorAll("time[data-at]"))
    el.textContent = relativeTime(Number(el.dataset.at), Date.now());
  if (loadedAt) updatedEl.textContent = `Updated ${relativeTime(loadedAt, Date.now())}`;
}

let toastTimer = 0;
function toast(message, tone = "") {
  clearTimeout(toastTimer);
  toastEl.className = `toast ${tone}`;
  toastEl.textContent = message;
  toastTimer = setTimeout(() => toastEl.classList.add("hide"), 5000);
}

const dialog = document.getElementById("confirm");
const dialogOk = document.getElementById("confirm-ok");
/** A modal yes/no. `danger` paints the confirm button red; Cancel has the focus. */
function confirmDialog({ title, body, confirm, danger = true }) {
  document.getElementById("confirm-title").textContent = title;
  document.getElementById("confirm-body").replaceChildren(...[body].flat());
  dialogOk.textContent = confirm;
  dialogOk.className = `btn ${danger ? "danger" : "primary"}`;
  dialog.returnValue = "";
  dialog.showModal();
  return new Promise((resolve) => {
    dialog.addEventListener("close", () => resolve(dialog.returnValue === "ok"), { once: true });
  });
}
dialogOk.addEventListener("click", () => dialog.close("ok"));
document.getElementById("confirm-cancel").addEventListener("click", () => dialog.close("cancel"));

const ICONS = {
  info: "M8 7.5v4M8 5v.01",
  good: "M5 8.2 7 10.2 11 6",
  warn: "M8 5.5v3.5M8 11v.01",
};
const icon = (kind) =>
  s(
    "svg",
    { viewBox: "0 0 16 16", "aria-hidden": "true" },
    s("circle", { cx: 8, cy: 8, r: 6.5 }),
    s("path", { d: ICONS[kind] || ICONS.info }),
  );
const searchIcon = () =>
  s(
    "svg",
    { viewBox: "0 0 16 16", "aria-hidden": "true" },
    s("circle", { cx: 7, cy: 7, r: 4.5 }),
    s("path", { d: "M10.5 10.5 14 14" }),
  );

const callout = (tone, title, body) =>
  h(
    "div",
    { class: `callout ${tone}`, role: tone === "bad" ? "alert" : null },
    icon(tone === "good" ? "good" : tone === "warn" || tone === "bad" ? "warn" : "info"),
    h("div", null, title && h("b", { text: title }), body && h("p", { text: body })),
  );

const pill = (tone, text, plain = false) =>
  h("span", { class: `pill ${tone}${plain ? " plain" : ""}`, text });

const statusPill = (config) => {
  const p = statePill(config);
  return pill(p.tone, p.text);
};

const pageHead = (title, lede, tools, crumbs) => [
  crumbs &&
    h(
      "nav",
      { class: "crumbs", "aria-label": "Breadcrumb" },
      crumbs.map(([label, href], i) => [
        i ? h("span", { "aria-hidden": "true", text: "/" }) : null,
        href ? h("a", { href, text: label }) : h("span", { text: label }),
      ]),
    ),
  h(
    "div",
    { class: "page-head" },
    h(
      "div",
      null,
      h("h1", { tabindex: "-1" }, title),
      lede && h("p", { class: "lede", text: lede }),
    ),
    tools && h("div", { class: "head-tools" }, tools),
  ),
];

/** An empty state that says what is missing and, where it helps, where it comes from. */
const empty = (title, ...body) =>
  h("div", { class: "empty" }, h("h3", { text: title }), body.length && h("p", null, body));

const section = (title, sub, ...kids) =>
  h(
    "section",
    { class: "section", "aria-label": title },
    h(
      "div",
      { class: "section-head" },
      h("h2", { class: "section-title", text: title }),
      sub && h("p", { class: "section-sub", text: sub }),
    ),
    kids,
  );

/* ---------- Data table ---------- */

/**
 * A GitHub-style table: a search box, optional filter buttons, sortable headers and rows that open
 * their detail page. Each column is { label, value(row) for sorting, cell(row), num }. The first
 * column's cell should hold a real link so the row is reachable by keyboard.
 */
function dataTable({
  caption,
  columns,
  rows,
  search,
  href,
  sort,
  filters,
  noun = "items",
  none,
  tools,
}) {
  const state = {
    query: "",
    filter: filters ? filters.options[0][0] : null,
    col: sort ? sort[0] : -1,
    dir: sort ? sort[1] : "asc",
  };
  const tbody = h("tbody");
  const counter = h("span", { class: "count", "aria-live": "polite" });
  const heads = columns.map((col, i) => {
    const th = h("th", { scope: "col", class: col.num ? "num" : null });
    if (col.value)
      th.append(
        h("button", {
          type: "button",
          class: "sort",
          text: col.label,
          onclick: () => {
            state.dir = state.col === i && state.dir === "asc" ? "desc" : "asc";
            if (state.col !== i) state.dir = col.num ? "desc" : "asc";
            state.col = i;
            draw();
          },
        }),
      );
    else th.textContent = col.label;
    return th;
  });

  const draw = () => {
    heads.forEach((th, i) => {
      if (i === state.col)
        th.setAttribute("aria-sort", state.dir === "asc" ? "ascending" : "descending");
      else th.removeAttribute("aria-sort");
    });
    let list = rows.filter(
      (row) =>
        (!search || matchesQuery(search(row), state.query)) &&
        (!filters || filters.test(row, state.filter)),
    );
    const col = columns[state.col];
    if (col && col.value) list = sortRows(list, col.value, state.dir);
    counter.textContent =
      list.length === rows.length ? `${rows.length} ${noun}` : `${list.length} of ${rows.length}`;
    tbody.replaceChildren(
      ...(list.length
        ? list.map((row) =>
            h(
              "tr",
              {
                class: href ? "link" : null,
                onclick: href
                  ? (e) => {
                      if (e.target.closest("a, button, input, select")) return;
                      location.hash = href(row);
                    }
                  : null,
              },
              columns.map((c) =>
                h("td", { class: c.num ? "num" : null }, c.cell ? c.cell(row) : c.value(row)),
              ),
            ),
          )
        : [
            h(
              "tr",
              null,
              h(
                "td",
                { colspan: String(columns.length) },
                rows.length
                  ? empty("Nothing matches", "Try another word, or clear the search.")
                  : none,
              ),
            ),
          ]),
    );
  };

  const filterBar =
    filters &&
    h(
      "div",
      { class: "seg", role: "group", "aria-label": filters.label },
      filters.options.map(([value, label]) => {
        const b = h("button", {
          type: "button",
          text: label,
          "aria-pressed": String(value === state.filter),
          onclick: () => {
            state.filter = value;
            for (const x of filterBar.children) x.setAttribute("aria-pressed", String(x === b));
            draw();
          },
        });
        return b;
      }),
    );

  draw();
  return h(
    "div",
    { class: "box" },
    (search || filters || tools) &&
      h(
        "div",
        { class: "table-tools" },
        search &&
          h(
            "label",
            { class: "search" },
            h("span", { class: "sr-only", text: `Search ${noun}` }),
            searchIcon(),
            h("input", {
              type: "search",
              placeholder: `Search ${noun}`,
              autocomplete: "off",
              spellcheck: "false",
              oninput: (e) => {
                state.query = e.currentTarget.value;
                draw();
              },
            }),
          ),
        filterBar,
        tools,
        counter,
      ),
    h(
      "div",
      { class: "table-wrap" },
      h(
        "table",
        null,
        h("caption", { class: "sr-only", text: caption }),
        h("thead", null, h("tr", null, heads)),
        tbody,
      ),
    ),
  );
}

/* ---------- Charts ---------- */

function sparkline(values, label) {
  const W = 96;
  const H = 32;
  const d = sparkPath(values, W, H);
  const known = values.filter((v) => v != null);
  return s(
    "svg",
    { class: "spark", viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": label },
    d && known.length > 1 && s("path", { class: "spark-area", d: `${d}V${H}H0Z` }),
    d && s("path", { d }),
  );
}

/** A share's 95% interval on a 0–100% track, for cards that have no daily series. */
function intervalMark(sh) {
  const W = 96;
  const x = (v) => 2 + v * (W - 4);
  const label =
    sh.share == null
      ? "No data yet"
      : `${fmtPct(sh.share)}, 95% interval ${fmtInterval(sh.interval)}`;
  return s(
    "svg",
    { class: "interval", viewBox: `0 0 ${W} 32`, role: "img", "aria-label": label },
    s("line", { class: "track", x1: 2, x2: W - 2, y1: 16, y2: 16 }),
    sh.interval &&
      s("path", {
        class: "ci",
        d: `M${x(sh.interval.low)},16H${x(sh.interval.high)}M${x(sh.interval.low)},12V20M${x(sh.interval.high)},12V20`,
      }),
    sh.share != null && s("circle", { class: "pt", cx: x(sh.share), cy: 16, r: 4 }),
  );
}

/**
 * Time-series chart over `days`. Each series is { label, values, mark: "line" | "area" | "bar", cls }.
 * One keyboard stop: arrow keys move a cursor, and the readout below says the day.
 */
function timeChart({ title, days, series }) {
  const H = 220;
  const m = { t: 12, r: 8, b: 28, l: 40 };
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
    .map((sr) => s("circle", { r: 4, class: sr.cls || null }));
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

  let active = -1;
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
        const bw = Math.max(1, slot() * 0.66);
        sr.bars = sr.values.map((v, i) =>
          s("rect", {
            class: "mark-bar",
            x: x(i) - bw / 2,
            y: y(v),
            width: bw,
            height: Math.max(0, m.t + ih - y(v)),
            rx: Math.min(2, bw / 3),
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
    text: "Hover, or focus and use the arrow keys, to read a day.",
  });

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
  // Redraw at the box's real pixel width so axis text stays 12px instead of scaling.
  new ResizeObserver(([entry]) => {
    const w = Math.round(entry.contentRect.width);
    if (w > 0 && w !== W) {
      W = Math.max(240, w);
      draw();
    }
  }).observe(box);

  const table = h(
    "div",
    { class: "table-wrap" },
    h(
      "table",
      null,
      h("caption", { class: "sr-only", text: title }),
      h(
        "thead",
        null,
        h(
          "tr",
          null,
          h("th", { scope: "col", text: "Day" }),
          series.map((x) => h("th", { scope: "col", class: "num", text: x.label })),
        ),
      ),
      h(
        "tbody",
        null,
        days.map((d, i) =>
          h(
            "tr",
            null,
            h("th", { scope: "row", text: fmtDay(d) }),
            series.map((x) => h("td", { class: "num", text: fmtNum(x.values[i]) })),
          ),
        ),
      ),
    ),
  );
  return [
    box,
    readout,
    h("details", { class: "data" }, h("summary", { text: "Show as table" }), table),
  ];
}

/* ---------- Overview ---------- */

const RANGES = [7, 30, 90];
const rangeFrom = (arg) => (RANGES.includes(Number(arg)) ? Number(arg) : 30);

const rangePicker = (route, days) =>
  h(
    "nav",
    { class: "seg", "aria-label": "Date range" },
    RANGES.map((d) =>
      h("a", {
        href: `#/${route}/${d}`,
        "aria-current": d === days ? "true" : null,
        text: `${d} days`,
      }),
    ),
  );

function statCard({ label, value, delta, foot, mark }) {
  return h(
    "div",
    { class: "box stat" },
    h("p", { class: "stat-label", text: label }),
    h("div", { class: "stat-row" }, h("p", { class: "stat-value", text: value }), mark),
    h(
      "p",
      { class: "stat-foot" },
      delta &&
        delta.kind !== "none" &&
        h("span", { class: `delta ${delta.kind}`, text: delta.text }),
      foot && h("span", { text: foot }),
    ),
  );
}

async function renderOverview([arg]) {
  const days = rangeFrom(arg);
  const o = await api(`/overview?days=${days}`);
  const st = o.stats;
  const vs = `vs previous ${days} days`;
  const hasEvents = o.totals.users > 0 || o.daily.some((d) => d.dau || d.notes);
  const range = `${fmtDay(o.range.from)} – ${fmtDay(o.range.to)}`;

  const countCard = (label, stat, fmt, fullLabel = label) =>
    statCard({
      label,
      value: stat.current == null ? "—" : fmt(stat.current),
      delta: deltaOf(stat.current, stat.previous),
      foot: vs,
      mark: sparkline(stat.series, `${fullLabel}, each day of the range`),
    });
  const shareCard = (label, stat, noun) =>
    statCard({
      label,
      value: fmtPct(stat.current.share),
      delta: deltaOf(stat.current.share ?? null, stat.previous.share ?? null, "pp"),
      foot: stat.current.of
        ? `${stat.current.count} of ${stat.current.of} ${noun}`
        : `No ${noun} in this range yet`,
      mark: intervalMark(stat.current),
    });

  const cards = h(
    "div",
    { class: "stats" },
    countCard("Daily active", st.dau, (v) => fmtNum(v, 1), "Daily active people"),
    countCard("Weekly active", st.wau, (v) => fmtNum(v, 0)),
    countCard("New pairs", st.newPairs, (v) => fmtNum(v, 0)),
    shareCard("Pair completion", st.pairCompletion, "inviters"),
    countCard("Notes per pair / day", st.notesPerPairPerDay, (v) => v.toFixed(2)),
    shareCard("D1 retention", st.d1, "pairs"),
    shareCard("D7 retention", st.d7, "pairs"),
  );

  const dayList = o.daily.map((d) => d.day);
  const activity = h(
    "div",
    { class: "box" },
    h(
      "div",
      { class: "box-head" },
      h("h3", { class: "box-title", text: "Active people" }),
      h(
        "p",
        { class: "legend", "aria-hidden": "true" },
        h("span", { text: "Daily" }),
        h("span", { class: "s2", text: "Weekly" }),
      ),
    ),
    timeChart({
      title: "Active people",
      days: dayList,
      series: [
        { label: "Daily", values: o.daily.map((d) => d.dau), mark: "area" },
        { label: "Weekly", values: o.daily.map((d) => d.wau), mark: "line", cls: "s2" },
      ],
    }),
  );
  const notes = h(
    "div",
    { class: "box" },
    h("div", { class: "box-head" }, h("h3", { class: "box-title", text: "Notes sent" })),
    timeChart({
      title: "Notes sent per day",
      days: dayList,
      series: [{ label: "Notes", values: o.daily.map((d) => d.notes), mark: "bar" }],
    }),
  );

  return [
    pageHead("Overview", `${range} · UTC days · compared with the ${days} days before`, [
      rangePicker("overview", days),
    ]),
    hasEvents
      ? [
          cards,
          h(
            "p",
            { class: "sub", style: { "margin-top": "12px" } },
            "Pair completion and retention count the inviters and pairs that started in the range. With a few dozen pairs one couple moves a rate by several points: hover a card's bar for its 95% interval.",
          ),
          section("Activity", null, h("div", { class: "grid two" }, activity, notes)),
        ]
      : h(
          "div",
          { class: "box" },
          empty(
            "No data yet",
            "Nothing is counted in D1 (",
            h("code", { text: "pair_events" }),
            ") yet. Numbers appear once someone signs in and opens the app on this stage.",
          ),
        ),
    section(
      "Funnel",
      "All time · each step's conversion from the one before",
      h("div", { class: "box" }, funnel(o.funnel)),
    ),
  ];
}

function funnel(stepsIn) {
  const steps = funnelSteps(stepsIn);
  const top = Math.max(1, ...steps.map((x) => x.count ?? 0));
  if (!steps.some((x) => x.count)) return empty("No funnel yet", "No one has signed in.");
  return h(
    "div",
    { class: "funnel", role: "table", "aria-label": "Funnel" },
    h(
      "div",
      { role: "row", style: { display: "contents" } },
      h("span", { class: "funnel-head", role: "columnheader", text: "Step" }),
      h("span", { class: "funnel-head bar", role: "columnheader", "aria-hidden": "true" }),
      h("span", { class: "funnel-head f-num", role: "columnheader", text: "People" }),
      h("span", { class: "funnel-head f-conv", role: "columnheader", text: "From step before" }),
    ),
    steps.map((st) =>
      h(
        "div",
        { role: "row", style: { display: "contents" } },
        h("span", { class: "f-label", role: "rowheader", text: st.label }),
        h(
          "span",
          { class: "f-track", "aria-hidden": "true" },
          st.count != null &&
            h("span", {
              class: "f-fill",
              style: { "--w": `${((st.count / top) * 100).toFixed(1)}%` },
            }),
        ),
        h("span", { class: "f-num", role: "cell", text: fmtNum(st.count) }),
        h("span", {
          class: "f-conv",
          role: "cell",
          text: st.fromPrevious == null ? "—" : fmtPct(st.fromPrevious),
        }),
        st.note && h("span", { class: "f-note", text: st.note }),
      ),
    ),
  );
}

/* ---------- In the app ---------- */

const TOP_TITLES = {
  CatChosen: "Cats chosen",
  ShopItemBought: "Items bought",
  ShopItemViewed: "Items looked at in the shop",
  ShopBundleBought: "Bundles bought",
  ShopOfferViewed: "Offers seen in the shop",
  ShopGiftSent: "Gifts bought for the partner",
  RoomItemPlaced: "Pieces put in the room",
  CatPlayed: "Toys played with",
  TrickDone: "Tricks done",
  TemperamentShown: "Temperaments shown",
  WidgetAdded: "Widgets added",
};

/** The most chosen cats, items, toys and the like, one box per event that has any. */
function mostChosen(top, range) {
  const shown = (top || []).filter((t) => t.items && t.items.length);
  const box = (t) =>
    h(
      "div",
      { class: "box" },
      h(
        "div",
        { class: "box-head" },
        h("h3", { class: "box-title", text: TOP_TITLES[t.name] || t.name }),
        h("span", { class: "sub mono", text: t.name }),
      ),
      h(
        "ol",
        { class: "top-list" },
        t.items.map((it) =>
          h(
            "li",
            null,
            h("span", { class: "mono", text: it.detail }),
            h(
              "span",
              { class: "top-count" },
              h("b", { text: fmtNum(it.count) }),
              it.total != null &&
                h("span", { class: "sub", text: ` · ${fmtNum(it.total)} stamps` }),
            ),
          ),
        ),
      ),
    );
  return section(
    "Most chosen",
    top ? `${range} · times chosen; items bought also show stamps spent` : null,
    shown.length
      ? h("div", { class: "grid tops" }, shown.map(box))
      : h(
          "div",
          { class: "box" },
          top
            ? empty(
                "Nothing chosen in this range",
                "Cats, shop items, room pieces, toys and tricks appear here once apps report them.",
              )
            : empty("Not available", "This server doesn't count chosen details yet."),
        ),
  );
}

async function renderEvents([arg, name]) {
  if (arg && !RANGES.includes(Number(arg))) return renderEvent(arg, rangeFrom(name));
  const days = rangeFrom(arg);
  const e = await api(`/app-events?days=${days}`);
  const range = `${fmtDay(e.range.from)} – ${fmtDay(e.range.to)}`;
  const seen = e.events.filter((x) => x.lastDay);
  const table = dataTable({
    caption: "Events from the app and the server",
    noun: "events",
    rows: e.events,
    sort: [2, "desc"],
    search: (x) => `${x.name} ${x.source}`,
    href: (x) => `#/events/${enc(x.name)}/${days}`,
    filters: {
      label: "Source",
      options: [
        ["all", "All"],
        ["app", "From the app"],
        ["server", "From the server"],
      ],
      test: (x, f) => f === "all" || x.source === f,
    },
    columns: [
      {
        label: "Event",
        value: (x) => x.name,
        cell: (x) =>
          h(
            "span",
            null,
            h("a", { class: "lead mono", href: `#/events/${enc(x.name)}/${days}`, text: x.name }),
          ),
      },
      {
        label: "Source",
        value: (x) => x.source,
        cell: (x) => pill("", x.source === "app" ? "app" : "server", true),
      },
      {
        label: `Last ${days} days`,
        num: true,
        value: (x) => x.total,
        cell: (x) => fmtNum(x.total),
      },
      {
        label: "Change",
        num: true,
        value: (x) => (x.previousTotal ? x.total / x.previousTotal : null),
        cell: (x) => {
          const d = deltaOf(x.total, x.previousTotal);
          return d.kind === "none"
            ? h("span", { class: "sub", text: "—" })
            : h("span", { class: `delta ${d.kind}`, text: d.text });
        },
      },
      { label: "Trend", cell: (x) => sparkline(x.daily, `${x.name} per day`) },
      {
        label: "Pairs, 7 days",
        num: true,
        value: (x) => x.pairs7d,
        cell: (x) => fmtNum(x.pairs7d),
      },
      { label: "People", num: true, value: (x) => x.people, cell: (x) => fmtNum(x.people) },
      {
        label: "Last landed",
        value: (x) => x.lastDay,
        cell: (x) =>
          x.lastDay ? h("span", { text: fmtDay(x.lastDay) }) : pill("warn", "not seen yet"),
      },
      {
        label: "First landed",
        value: (x) => x.firstDay,
        cell: (x) => (x.firstDay ? fmtDay(x.firstDay) : "—"),
      },
    ],
    none: empty("No events", "The contract lists none."),
  });
  return [
    pageHead(
      "In the app",
      `${range} · what the app and the server count, and when each event landed`,
      [rangePicker("events", days)],
    ),
    seen.length
      ? null
      : h(
          "div",
          { style: { "margin-bottom": "16px" } },
          callout(
            "warn",
            "No events recorded yet",
            "D1 has no pair_events rows on this stage. The app reports after sign-in; the server counts invites, pairs and notes as they happen.",
          ),
        ),
    table,
    h(
      "p",
      { class: "sub", style: { "margin-top": "12px" } },
      "Counts come from D1 (pair_events) by UTC day. An event the app does not send yet shows “not seen yet” until its first report lands.",
    ),
    mostChosen(e.top, range),
  ];
}

async function renderEvent(name, days) {
  const e = await api(`/app-events?days=${days}`);
  const x = e.events.find((ev) => ev.name === name);
  const crumbs = [["In the app", `#/events/${days}`], [name]];
  if (!x)
    return [
      pageHead(name, null, null, crumbs),
      h("div", { class: "box" }, empty("No such event", "It isn't in the event contract.")),
    ];
  const d = deltaOf(x.total, x.previousTotal);
  return [
    pageHead(
      h("span", { class: "mono", text: name }),
      `${x.source === "app" ? "Sent by the app" : "Counted by the server"} · ${fmtDay(e.range.from)} – ${fmtDay(e.range.to)}`,
      [rangePicker(`events/${enc(name)}`, days)],
      crumbs,
    ),
    h(
      "div",
      { class: "stats" },
      statCard({
        label: `Total, ${days} days`,
        value: fmtNum(x.total),
        delta: d,
        foot: `vs previous ${days} days`,
      }),
      statCard({
        label: "Pairs, last 7 days",
        value: fmtNum(x.pairs7d),
        foot: "did it at least once",
      }),
      statCard({ label: "People in range", value: fmtNum(x.people) }),
      statCard({
        label: "Landed",
        value: x.lastDay ? fmtDay(x.lastDay) : "—",
        foot: x.firstDay ? `first on ${fmtDay(x.firstDay)}` : "never recorded",
      }),
    ),
    section(
      "Per day",
      null,
      h(
        "div",
        { class: "box" },
        x.total
          ? timeChart({
              title: `${name} per day`,
              days: e.days,
              series: [{ label: name, values: x.daily, mark: "bar" }],
            })
          : empty(
              "None in this range",
              x.lastDay ? `Last seen ${fmtDay(x.lastDay)}.` : "It has never been recorded.",
            ),
      ),
    ),
  ];
}

/* ---------- Experiments ---------- */

const ACTIONS = {
  start: {
    label: "Start",
    cls: "primary",
    done: "started",
    title: (k) => `Start ${k}?`,
    body: "New pairs start entering it at its exposure and split. Pairs already assigned keep their variant.",
    danger: false,
  },
  stop: {
    label: "Stop",
    cls: "",
    done: "stopped",
    title: (k) => `Stop ${k}?`,
    body: "No new pairs enter it. Pairs already in it keep their variant until you kill it.",
    danger: true,
  },
  kill: {
    label: "Kill",
    cls: "danger",
    done: "killed",
    title: (k) => `Kill ${k}?`,
    body: "Every pair gets the default variant right away, whatever they were assigned. You can unkill it later.",
    danger: true,
  },
  unkill: {
    label: "Unkill",
    cls: "",
    done: "unkilled",
    title: (k) => `Unkill ${k}?`,
    body: "Pairs go back to their assigned variants.",
    danger: false,
  },
};

async function runAction(item, action) {
  const a = ACTIONS[action];
  const ok = await confirmDialog({
    title: a.title(item.key),
    body: a.body,
    confirm: `${a.label} ${item.kind}`,
    danger: a.danger,
  });
  if (!ok) return;
  try {
    await api(`/experiments/${enc(item.key)}/${action}`, {
      method: "POST",
      body: { expectedVersion: item.version },
    });
    toast(`${item.key} ${a.done}.`);
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

const actionButtons = (item) =>
  experimentActions(item.config).map((action) =>
    h("button", {
      type: "button",
      class: `btn ${ACTIONS[action].cls}`,
      text: ACTIONS[action].label,
      onclick: () => runAction(item, action),
    }),
  );

const VERDICT_TONE = { "no-data": "info", overlap: "warn", ahead: "good" };
const verdictShort = (r) =>
  !r || !r.verdict
    ? h("span", { class: "sub", text: "No pairs yet" })
    : r.verdict.kind === "ahead"
      ? pill("good", `${r.verdict.leader} ahead`)
      : r.verdict.kind === "overlap" && !r.verdict.small
        ? pill("", "no difference yet")
        : pill("", "not enough data", true);

/** "Title: the rest." as a callout's bold line and its body. */
const verdictLines = (text) => {
  const at = text.indexOf(": ");
  if (at < 0) return [text, null];
  const rest = text.slice(at + 2);
  return [text.slice(0, at), rest.charAt(0).toUpperCase() + rest.slice(1)];
};

const pairsIn = (it) => (it.results ? it.results.variants.reduce((a, v) => a + v.pairs, 0) : 0);

async function renderExperiments([key]) {
  if (key) return renderExperiment(key);
  const { items } = await api("/experiments");
  const exps = items.filter((i) => i.kind === "experiment");
  return [
    pageHead(
      "Experiments",
      "Assignment is per pair. The north star: both partners sent a note on day 7.",
    ),
    dataTable({
      caption: "Experiments",
      noun: "experiments",
      rows: exps,
      search: (i) => `${i.key} ${i.config.description || ""} ${statePill(i.config).text}`,
      href: (i) => `#/experiments/${enc(i.key)}`,
      sort: [0, "asc"],
      filters: {
        label: "Status",
        options: [
          ["all", "All"],
          ["running", "Running"],
          ["stopped", "Stopped"],
          ["draft", "Draft"],
          ["killed", "Killed"],
        ],
        test: (i, f) => f === "all" || statePill(i.config).text === f,
      },
      columns: [
        {
          label: "Experiment",
          value: (i) => i.key,
          cell: (i) => [
            h("a", { class: "lead mono", href: `#/experiments/${enc(i.key)}`, text: i.key }),
            i.config.description && h("span", { class: "sub", text: i.config.description }),
          ],
        },
        {
          label: "Status",
          value: (i) => statePill(i.config).text,
          cell: (i) => statusPill(i.config),
        },
        {
          label: "Exposure",
          num: true,
          value: (i) => i.config.exposure,
          cell: (i) => `${fmtNum(i.config.exposure)}%`,
        },
        {
          label: "Variants",
          num: true,
          value: (i) => i.variants.length,
          cell: (i) => String(i.variants.length),
        },
        { label: "Pairs", num: true, value: pairsIn, cell: (i) => fmtNum(pairsIn(i)) },
        {
          label: "Result",
          value: (i) => i.results?.verdict?.kind ?? null,
          cell: (i) => verdictShort(i.results),
        },
        { label: "Changed", value: (i) => i.updatedAt, cell: (i) => ago(i.updatedAt) },
      ],
      none: empty(
        "No experiments yet",
        "Experiments defined in code (flags registry) show up here once deployed.",
      ),
    }),
  ];
}

/** Every variant's north star on one shared axis: the dot is the estimate, the bar its 95% interval. */
function forest(variants, leader) {
  const rowH = 36;
  const highest = Math.max(0.1, ...variants.map((v) => v.northStar.interval?.high ?? 0));
  const step = highest <= 0.4 ? 0.1 : 0.2;
  const top = Math.min(1, Math.ceil(highest / step) * step);
  const H = variants.length * rowH + 28;
  const svg = s("svg", {
    role: "img",
    "aria-label": `North star by variant: ${variants.map((v) => `${v.variant} ${fmtPct(v.northStar.share)} (95% ${fmtInterval(v.northStar.interval)})`).join("; ")}`,
  });
  const draw = (W) => {
    const L = Math.min(180, W * 0.25);
    const R = 140;
    const x = (v) => L + (v / top) * (W - L - R);
    svg.setAttribute("viewBox", `0 0 ${W} ${H}`);
    svg.replaceChildren();
    for (let v = 0; v <= top + 1e-9; v += step) {
      svg.append(
        s("line", { class: "grid-line", x1: x(v), x2: x(v), y1: 0, y2: H - 20 }),
        s("text", { class: "val", x: x(v), y: H - 4, "text-anchor": "middle", text: fmtPct(v, 0) }),
      );
    }
    variants.forEach((v, i) => {
      const cy = i * rowH + rowH / 2;
      const n = v.northStar;
      svg.append(
        s(
          "g",
          { class: v.variant === leader ? "leader" : null },
          s("text", { class: "label", x: 0, y: cy + 4, text: v.variant }),
          n.interval &&
            s("path", {
              class: "ci",
              d: `M${x(n.interval.low)},${cy}H${x(n.interval.high)}M${x(n.interval.low)},${cy - 6}V${cy + 6}M${x(n.interval.high)},${cy - 6}V${cy + 6}`,
            }),
          n.share != null && s("circle", { class: "pt", cx: x(n.share), cy, r: 5 }),
          s("text", {
            class: "val",
            x: W,
            y: cy + 4,
            "text-anchor": "end",
            text: n.of ? `${fmtPct(n.share)} · ${fmtInterval(n.interval)}` : "no pairs at day 7",
          }),
        ),
      );
    });
  };
  const box = h("div", { class: "box forest", style: { "margin-top": "16px" } }, svg);
  let W = 720;
  draw(W);
  new ResizeObserver(([entry]) => {
    const w = Math.round(entry.contentRect.width);
    if (w > 0 && w !== W) draw((W = Math.max(320, w)));
  }).observe(box);
  return box;
}

async function renderExperiment(key) {
  const [{ items }, { changes }] = await Promise.all([
    api("/experiments"),
    api(`/history?key=${enc(key)}&limit=20`),
  ]);
  const item = items.find((i) => i.key === key);
  const crumbs = [["Experiments", "#/experiments"], [key]];
  if (!item)
    return [
      pageHead(key, null, null, crumbs),
      h(
        "div",
        { class: "box" },
        empty("No such experiment", "It may have been removed from the code."),
      ),
    ];
  const c = item.config;
  const r = item.results;
  const shares = splitShares(c.weights);
  const verdict = r?.verdict;
  const leader = verdict?.kind === "ahead" ? verdict.leader : null;

  const variants = item.variants.map((id) => {
    const v = r?.variants.find((x) => x.variant === id);
    return h(
      "article",
      { class: `box variant${id === leader ? " leader" : ""}` },
      h(
        "h3",
        null,
        id,
        id === leader ? pill("good", "ahead") : id === c.default ? pill("", "default", true) : null,
      ),
      h(
        "dl",
        null,
        h("div", null, h("dt", { text: "Split" }), h("dd", { text: fmtPct(shares[id] ?? 0, 0) })),
        h("div", null, h("dt", { text: "Pairs" }), h("dd", { text: fmtNum(v?.pairs ?? 0) })),
        h(
          "div",
          null,
          h("dt", { text: "North star" }),
          h(
            "dd",
            null,
            v ? fmtPct(v.northStar.share) : "—",
            v &&
              h("span", {
                class: "sub",
                text: v.northStar.of
                  ? `95% ${fmtInterval(v.northStar.interval)} · ${v.northStar.count} of ${v.northStar.of}`
                  : "no pairs at day 7",
              }),
          ),
        ),
        h(
          "div",
          null,
          h("dt", { text: "Median to first note" }),
          h("dd", { text: fmtDuration(v?.medianToFirstNote) }),
        ),
      ),
    );
  });

  return [
    pageHead(
      [h("span", { class: "mono", text: key }), statusPill(c)],
      c.description || null,
      actionButtons(item),
      crumbs,
    ),
    h(
      "p",
      { class: "meta" },
      h("span", null, "Exposure ", h("b", { text: `${fmtNum(c.exposure)}%` })),
      h("span", null, "Default ", h("b", { class: "mono", text: c.default })),
      h(
        "span",
        null,
        "Version ",
        h("b", { text: item.version ? `v${item.version}` : "never edited" }),
      ),
      h(
        "span",
        null,
        "Changed ",
        ago(item.updatedAt),
        item.updatedBy ? ` by ${item.updatedBy}` : "",
      ),
      h("a", { href: `#/flags/${enc(key)}`, text: "Edit configuration →" }),
    ),
    section(
      "Result",
      "North star: both partners sent a note on day 7",
      verdict
        ? callout(VERDICT_TONE[verdict.kind], ...verdictLines(verdict.text))
        : callout("info", "Not enough data yet", "No pair has been assigned to this experiment."),
      r && r.variants.length ? forest(r.variants, leader) : null,
    ),
    section("Variants", null, h("div", { class: "variants" }, variants)),
    section("History", null, h("div", { class: "box" }, historyList(changes, { showKey: false }))),
  ];
}

/* ---------- Flags ---------- */

const showValue = (v) =>
  v === undefined || v === null ? "none" : Array.isArray(v) ? v.join(", ") || "none" : String(v);

function diffView(before, after) {
  const rows = diffConfig(before, after);
  if (!rows.length) return null;
  return h(
    "ul",
    { class: "diff" },
    rows.map((d) =>
      h(
        "li",
        null,
        h("span", { class: "path", text: d.path }),
        h(
          "span",
          null,
          d.before !== undefined && h("span", { class: "was", text: showValue(d.before) }),
          d.after !== undefined && h("span", { class: "now", text: showValue(d.after) }),
        ),
      ),
    ),
  );
}

function historyList(changes, { showKey }) {
  if (!changes.length)
    return empty(
      "No changes yet",
      "Every save, start, stop and kill is listed here with who made it.",
    );
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
          h("b", { text: c.by }),
          pill("", c.action, true),
          showKey && h("a", { class: "mono", href: `#/flags/${enc(c.key)}`, text: c.key }),
          c.pairId && h("span", { class: "mono", text: `pair ${c.pairId}` }),
          ago(c.at),
        ),
        diffView(c.before, c.after),
      ),
    ),
  );
}

async function renderFlags([key]) {
  if (key) return renderFlag(key);
  const { items } = await api("/flags");
  return [
    pageHead(
      "Flags",
      "Every experiment and remote flag the code declares, with its live configuration.",
    ),
    dataTable({
      caption: "Flags and experiments",
      noun: "flags",
      rows: items,
      search: (i) => `${i.key} ${i.kind} ${i.config.description || ""} ${i.updatedBy || ""}`,
      href: (i) => `#/flags/${enc(i.key)}`,
      sort: [0, "asc"],
      filters: {
        label: "Kind",
        options: [
          ["all", "All"],
          ["flag", "Flags"],
          ["experiment", "Experiments"],
        ],
        test: (i, f) => f === "all" || i.kind === f,
      },
      columns: [
        {
          label: "Key",
          value: (i) => i.key,
          cell: (i) => [
            h("a", { class: "lead mono", href: `#/flags/${enc(i.key)}`, text: i.key }),
            i.config.description && h("span", { class: "sub", text: i.config.description }),
          ],
        },
        { label: "Kind", value: (i) => i.kind, cell: (i) => pill("", i.kind, true) },
        {
          label: "State",
          value: (i) => statePill(i.config).text,
          cell: (i) => statusPill(i.config),
        },
        {
          label: "Serving",
          value: (i) => i.config.default,
          cell: (i) => {
            const sh = splitShares(i.config.weights);
            const live = Object.entries(sh).filter(([, x]) => x > 0);
            const text =
              i.config.killed || i.config.status !== "running" || live.length === 0
                ? i.config.default
                : live.length === 1
                  ? live[0][0]
                  : live.map(([v, x]) => `${v} ${fmtPct(x, 0)}`).join(" · ");
            return h("span", { class: "mono", text });
          },
        },
        {
          label: "Exposure",
          num: true,
          value: (i) => i.config.exposure,
          cell: (i) => `${fmtNum(i.config.exposure)}%`,
        },
        {
          label: "Version",
          num: true,
          value: (i) => i.version,
          cell: (i) => (i.version ? `v${i.version}` : "—"),
        },
        {
          label: "Changed",
          value: (i) => i.updatedAt,
          cell: (i) =>
            i.version
              ? [ago(i.updatedAt), h("span", { class: "sub", text: i.updatedBy || "" })]
              : h("span", { class: "sub", text: "never edited" }),
        },
      ],
      none: empty(
        "Nothing defined yet",
        "Flags and experiments appear here once the backend declares them.",
      ),
    }),
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

async function renderFlag(key) {
  const [{ items }, { changes }] = await Promise.all([
    api("/flags"),
    api(`/history?key=${enc(key)}&limit=50`),
  ]);
  const crumbs = [["Flags", "#/flags"], [key]];
  const item = items.find((i) => i.key === key);
  if (!item)
    return [
      pageHead(key, null, null, crumbs),
      h(
        "div",
        { class: "box" },
        empty("No such flag", "It may have been removed from the code. Pick one from the list."),
      ),
    ];
  const c = item.config;
  const t = c.targeting || {};

  const desc = h("textarea", { rows: "2", text: c.description || "" });
  const weightInputs = new Map();
  const outputs = new Map();
  const updateSplit = () => {
    const sh = splitShares(
      Object.fromEntries(
        [...weightInputs].map(([v, i]) => [
          v,
          Number.isFinite(i.valueAsNumber) ? i.valueAsNumber : 0,
        ]),
      ),
    );
    for (const [v, o] of outputs) o.textContent = fmtPct(sh[v], 0);
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
  const versionInput = (value, placeholder) =>
    h("input", {
      type: "text",
      pattern: VERSION_PATTERN,
      placeholder,
      value: value || "",
      autocomplete: "off",
      spellcheck: "false",
    });
  const minV = versionInput(t.minAppVersion, "e.g. 1.4");
  const maxV = versionInput(t.maxAppVersion, "e.g. 2.0+120");
  const bands = ["13-17", "18+"].map((b) => [
    b,
    h("input", { type: "checkbox", checked: (t.ageBands || []).includes(b) }),
  ]);
  const pairIds = h("textarea", {
    class: "mono",
    rows: "3",
    spellcheck: "false",
    text: (t.pairIds || []).join("\n"),
  });
  const msg = h("div", { class: "form-msg", role: "alert", tabindex: "-1" });
  const save = h("button", { type: "submit", class: "btn primary", text: "Review changes" });
  const discard = h("button", {
    type: "button",
    class: "btn quiet",
    text: "Discard edits",
    onclick: () => route(),
  });
  const reviewSlot = h("div");

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

  const closeReview = () => {
    reviewSlot.replaceChildren();
    save.hidden = false;
  };

  async function send(config, btn) {
    btn.disabled = true;
    try {
      await api(`/flags/${enc(key)}`, {
        method: "PUT",
        body: { config, expectedVersion: item.version },
      });
      toast(`Saved ${key}.`);
      route();
    } catch (err) {
      btn.disabled = false;
      closeReview();
      if (err.status === 409) {
        msg.replaceChildren(
          h("p", {
            text: `Someone else changed ${key} while you were editing (now v${err.body?.current ?? "?"}). Load the latest, then re-apply your edits.`,
          }),
          h(
            "div",
            { class: "actions", style: { "margin-top": "8px" } },
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
      msg.focus();
    }
  }

  const review = (config) => {
    const diff = diffView(c, config);
    const title = h("h3", {
      class: "box-title",
      tabindex: "-1",
      text: diff ? "Review before saving" : "Nothing changed",
    });
    const confirm = h("button", {
      type: "button",
      class: "btn primary",
      text: `Save v${item.version + 1}`,
    });
    confirm.addEventListener("click", () => send(config, confirm));
    reviewSlot.replaceChildren(
      h(
        "div",
        { class: "review", role: "group", "aria-label": "Changes to save" },
        h(
          "div",
          { class: "box-head" },
          title,
          h("span", { class: "sub", text: `v${item.version} → v${item.version + 1}` }),
        ),
        diff || h("p", { class: "box-pad sub", text: "The form matches what is live." }),
        h(
          "div",
          { class: "form-foot" },
          diff && confirm,
          h("button", {
            type: "button",
            class: "btn",
            text: "Keep editing",
            onclick: () => {
              closeReview();
              save.focus();
            },
          }),
        ),
      ),
    );
    save.hidden = true;
    title.focus();
  };

  const form = h(
    "form",
    {
      class: "box form",
      novalidate: true,
      "aria-label": `Edit ${key}`,
      oninput: closeReview,
      onsubmit: (e) => {
        e.preventDefault();
        msg.replaceChildren();
        if (!form.reportValidity()) return;
        review(readConfig());
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
        text: "Weight per variant, and the split it gives",
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
        "div",
        { class: "field", role: "group", "aria-labelledby": `${key}-ages` },
        h("p", { class: "label", id: `${key}-ages`, text: "Age bands" }),
        h(
          "div",
          null,
          bands.map(([b, el]) => h("label", { class: "check" }, el, b)),
        ),
        h("p", {
          class: "hint",
          text: "None checked means everyone. The server doesn't know age bands yet, so checking one excludes everyone for now.",
        }),
      ),
      field("Pair ids", pairIds, "One per line. Blank means all pairs."),
    ),
    msg,
    reviewSlot,
    h(
      "div",
      { class: "form-foot" },
      save,
      discard,
      h(
        "p",
        { class: "hint" },
        item.version
          ? [
              `v${item.version} · changed `,
              ago(item.updatedAt),
              ` by ${item.updatedBy || "unknown"}`,
            ]
          : "Never edited",
      ),
    ),
  );

  return [
    pageHead(
      [h("span", { class: "mono", text: key }), statusPill(c)],
      `${item.kind} · ${item.variants.length} variants${c.description ? ` · ${c.description}` : ""}`,
      item.kind === "experiment"
        ? h("a", { class: "btn", href: `#/experiments/${enc(key)}`, text: "Results" })
        : null,
      crumbs,
    ),
    h("div", { class: "narrow" }, form),
    section(
      "Change history",
      "Newest first, with who made each change",
      h("div", { class: "box" }, historyList(changes, { showKey: false })),
    ),
  ];
}

/* ---------- Pairs ---------- */

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
  if (!variant) {
    const ok = await confirmDialog({
      title: `Clear the override for ${key}?`,
      body: "This pair goes back to what the rules give it.",
      confirm: "Clear override",
    });
    if (!ok) return;
  }
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
    class: "mono",
  });
  const lookup = h(
    "form",
    {
      class: "inline",
      role: "search",
      style: { "max-width": "480px" },
      onsubmit: (e) => {
        e.preventDefault();
        const id = input.value.trim();
        if (id) location.hash = `#/pairs/${enc(id)}`;
      },
    },
    input,
    h("button", { type: "submit", class: "btn primary", text: "Look up" }),
  );
  const head = pageHead(
    "Pairs",
    "One pair by its id. There is no search by person, by design.",
    lookup,
  );
  if (!pairId)
    return [
      head,
      h(
        "div",
        { class: "box" },
        empty(
          "Enter a pair id",
          "You'll see its assignments, overrides, the decision for every flag, and its event counts.",
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
      h(
        "div",
        { class: "box" },
        empty("No pair with that id", "Check the id and try again. Ids are case-sensitive."),
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

  const rows = keys.map((key) => ({
    key,
    d: decisions.get(key),
    a: assigned.get(key),
    o: overrides.get(key),
    f: byKey.get(key),
  }));
  const table = dataTable({
    caption: "Decisions, assignments and overrides",
    noun: "flags",
    rows,
    search: (r) => r.key,
    sort: [0, "asc"],
    columns: [
      {
        label: "Flag",
        value: (r) => r.key,
        cell: (r) => h("a", { class: "lead mono", href: `#/flags/${enc(r.key)}`, text: r.key }),
      },
      {
        label: "Gets now",
        value: (r) => r.d?.variant ?? null,
        cell: (r) => [
          r.d && r.d.variant != null
            ? h("b", { class: "mono", text: r.d.variant })
            : h("span", { class: "sub", text: "not listed" }),
          r.d && h("span", { class: "sub", text: REASONS[r.d.reason] || r.d.reason }),
        ],
      },
      {
        label: "Stored",
        value: (r) => r.a?.variant ?? null,
        cell: (r) =>
          r.a
            ? [
                h("span", { class: "mono", text: r.a.variant }),
                h("span", { class: "sub" }, ago(r.a.assignedAt)),
              ]
            : "—",
      },
      {
        label: "Override",
        value: (r) => r.o?.variant ?? null,
        cell: (r) =>
          r.o
            ? [
                pill("warn", r.o.variant),
                h("span", { class: "sub" }, `${r.o.setBy}, `, ago(r.o.setAt)),
              ]
            : "—",
      },
      {
        label: "Change",
        cell: (r) => {
          if (!r.f) return h("span", { class: "sub", text: "Not in the flag list" });
          const sel = h(
            "select",
            { "aria-label": `Override variant for ${r.key}`, style: { width: "auto" } },
            r.f.variants.map((v) =>
              h("option", {
                value: v,
                text: v,
                selected: r.o ? v === r.o.variant : v === r.f.config.default,
              }),
            ),
          );
          return h(
            "div",
            { class: "inline" },
            sel,
            h("button", {
              type: "button",
              class: "btn",
              text: "Set",
              "aria-label": `Set override for ${r.key}`,
              onclick: () => overrideAction(pair.pairId, r.key, sel.value),
            }),
            r.o &&
              h("button", {
                type: "button",
                class: "btn quiet",
                text: "Clear",
                "aria-label": `Clear override for ${r.key}`,
                onclick: () => overrideAction(pair.pairId, r.key, null),
              }),
          );
        },
      },
    ],
    none: empty("No flags defined"),
  });

  const events = [...pair.events].sort((a, b) => b.count - a.count);
  return [
    head,
    h(
      "div",
      { class: "box box-pad" },
      h(
        "dl",
        { class: "facts", style: { "margin-top": "0" } },
        h("div", null, h("dt", { text: "Pair id" }), h("dd", { class: "mono", text: pair.pairId })),
        h(
          "div",
          null,
          h("dt", { text: "Analytics hash" }),
          h("dd", { class: "mono", text: pair.pairHash }),
        ),
        h("div", null, h("dt", { text: "Members" }), h("dd", { text: fmtNum(pair.members) })),
        h(
          "div",
          null,
          h("dt", { text: "Paired" }),
          h("dd", null, pair.pairedAt ? ago(pair.pairedAt) : "Not yet"),
        ),
      ),
    ),
    section(
      "Flags and experiments for this pair",
      "Overrides are for testing on your own phones",
      table,
    ),
    section(
      "Events",
      "All time, from D1",
      dataTable({
        caption: "Event counts",
        noun: "events",
        rows: events,
        sort: [1, "desc"],
        columns: [
          {
            label: "Event",
            value: (e) => e.name,
            cell: (e) => h("span", { class: "mono", text: e.name }),
          },
          { label: "Count", num: true, value: (e) => e.count, cell: (e) => fmtNum(e.count) },
        ],
        none: empty("No events", "Nothing recorded for this pair."),
      }),
    ),
  ];
}

/* ---------- Maintenance ---------- */

const MESSAGE_KEY_PATTERN = "^[a-z0-9]+(?:[.\\-][a-z0-9]+){0,7}$";
const NORMAL_STATUS = { maintenance: { active: false } };
const localZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
const pad2 = (n) => String(n).padStart(2, "0");

/** A UTC instant as the value of a `datetime-local` input, in the browser's zone. */
function toLocalInput(iso) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}T${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

/** A `datetime-local` value, read in the browser's zone, as `YYYY-MM-DDTHH:MM:SSZ`. */
function fromLocalInput(value) {
  if (!value) return undefined;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return undefined;
  return d.toISOString().replace(/\.\d{3}Z$/, "Z");
}

const clip = (text, n = 60) => (text.length > n ? `${text.slice(0, n - 1)}…` : text);
const sameMessage = (a, b) => (a?.key ?? null) === (b?.key ?? null) && a?.text === b?.text;
/** Product analytics is on unless the status says `analytics.enabled: false`. */
const analyticsOn = (status) => status.analytics?.enabled !== false;

/** What one saved status changed against the one before it, or the whole state without one. */
function statusSummary(status, prev) {
  const m = status.maintenance;
  const pm = prev?.maintenance;
  const parts = [];
  if (!prev || m.active !== pm.active) parts.push(m.active ? "Maintenance on" : "Maintenance off");
  if (prev ? m.until !== pm.until : m.until)
    parts.push(m.until ? `until ${fmtInstant(m.until)}` : "until cleared");
  if (prev ? !sameMessage(m.message, pm.message) : m.message)
    parts.push(m.message ? `message “${clip(m.message.text)}”` : "message removed");
  if (prev ? status.minVersion !== prev.minVersion : status.minVersion)
    parts.push(status.minVersion ? `min version ${status.minVersion}` : "min version removed");
  if (prev ? !sameMessage(status.notice, prev.notice) : status.notice)
    parts.push(status.notice ? `notice “${clip(status.notice.text)}”` : "notice removed");
  if (prev ? analyticsOn(status) !== analyticsOn(prev) : !analyticsOn(status))
    parts.push(analyticsOn(status) ? "analytics on" : "analytics off");
  return parts.length ? parts.join(" · ") : "Saved with no changes";
}

const backAroundFmt = new Intl.DateTimeFormat("en-GB", { hour: "2-digit", minute: "2-digit" });

/**
 * Roughly how the app shows this status (MaintenanceView in the iOS app): the sleeping room with a
 * card of the message, "Back around …" and the safe-notes line; or the room with the notice.
 */
function phonePreview(status) {
  const m = status.maintenance;
  const screen = m.active
    ? h(
        "div",
        { class: "phone-card" },
        h("b", { text: m.message?.text || "billet is resting for a little while." }),
        m.until &&
          h("span", {
            class: "phone-gold",
            text: `Back around ${backAroundFmt.format(Date.parse(m.until))}`,
          }),
        h("span", {
          text: "Your notes are safe here, and anything you send waits until billet is back.",
        }),
        h("span", { class: "phone-btn", text: "Read your notes" }),
      )
    : status.notice && h("div", { class: "phone-notice", text: status.notice.text });
  return h(
    "div",
    { class: "preview" },
    h("p", {
      class: "preview-label",
      text: m.active ? "In the app: the maintenance screen" : "In the app",
    }),
    h("div", { class: `phone${m.active ? " resting" : ""}`, "aria-hidden": "true" }, screen),
    h("p", {
      class: "hint",
      text: status.minVersion
        ? `Builds older than ${status.minVersion} see only “Update billet”.`
        : "No minimum build.",
    }),
  );
}

let statusNotice = "";

async function renderMaintenance() {
  const [current, { changes }] = await Promise.all([
    api("/status"),
    api("/status/history?limit=50"),
  ]);
  const st = current.status;
  const m = st.maintenance;

  const notice = statusNotice
    ? h(
        "div",
        { style: { "margin-bottom": "16px" } },
        callout("warn", "Showing the latest", statusNotice),
      )
    : null;
  statusNotice = "";

  const active = h("input", {
    type: "checkbox",
    role: "switch",
    checked: m.active,
    "aria-describedby": "switch-hint",
  });
  const keyInput = (value) =>
    h("input", {
      type: "text",
      class: "mono",
      pattern: MESSAGE_KEY_PATTERN,
      maxlength: "80",
      value,
      autocomplete: "off",
      spellcheck: "false",
    });
  const textInput = (value) => h("textarea", { rows: "2", maxlength: "280", text: value });

  const msgKey = keyInput(m.message?.key || "maintenance.default");
  const msgText = textInput(m.message?.text || "");
  const untilStart = m.until ? toLocalInput(m.until) : "";
  const until = h("input", { type: "datetime-local", max: "9999-12-31T23:59", value: untilStart });
  const untilHint = h("p", { class: "hint", id: "until-hint" });
  const showUntil = () => {
    const iso = fromLocalInput(until.value);
    if (!iso) {
      untilHint.textContent = `Blank means no time is shown. Your time zone: ${localZone}.`;
      return;
    }
    const past = Date.parse(iso) < Date.now() ? " This is in the past." : "";
    untilHint.textContent = `${fmtWhen(Date.parse(iso))} your time (${localZone}) · sent as ${iso}.${past}`;
  };
  until.setAttribute("aria-describedby", "until-hint");
  const clearUntil = h("button", {
    type: "button",
    class: "btn quiet",
    text: "Clear",
    "aria-label": "Clear until",
    onclick: () => {
      until.value = "";
      refresh();
      until.focus();
    },
  });

  const minV = h("input", {
    type: "text",
    pattern: VERSION_PATTERN,
    placeholder: "e.g. 1.2 or 1.2.0+14",
    value: st.minVersion || "",
    autocomplete: "off",
    spellcheck: "false",
  });
  const noticeKey = keyInput(st.notice?.key || "notice.default");
  const noticeText = textInput(st.notice?.text || "");
  const analyticsWasOn = analyticsOn(st);
  const analytics = h("input", {
    type: "checkbox",
    role: "switch",
    checked: analyticsWasOn,
    "aria-describedby": "analytics-hint",
  });
  const analyticsState = h("span", { class: "sub" });

  const readStatus = () => {
    const maintenance = { active: active.checked };
    const mt = msgText.value.trim();
    if (mt) maintenance.message = { key: msgKey.value.trim(), text: mt };
    const iso = until.value === untilStart ? m.until : fromLocalInput(until.value);
    if (iso) maintenance.until = iso;
    const status = { maintenance };
    if (minV.value.trim()) status.minVersion = minV.value.trim();
    const nt = noticeText.value.trim();
    if (nt) status.notice = { key: noticeKey.value.trim(), text: nt };
    if (!analytics.checked) status.analytics = { enabled: false };
    return status;
  };

  const msg = h("div", { class: "form-msg", role: "alert", tabindex: "-1" });
  const save = h("button", { type: "submit", class: "btn primary", text: "Save" });
  const stateTitle = h("h2");
  const stateSub = h("p", { class: "sub" });
  const previewSlot = h("div");
  const card = h("div", { class: "box status-card" });

  const refresh = () => {
    showUntil();
    const on = active.checked;
    card.classList.toggle("on", on);
    stateTitle.textContent = on
      ? m.active
        ? "Maintenance is on"
        : "Maintenance will turn on"
      : m.active
        ? "Maintenance will turn off"
        : "Running normally";
    stateSub.textContent = `${
      on
        ? "Every write is refused for everyone: no notes, no pairing, no settings."
        : "Apps work as usual."
    } ${analytics.checked ? "Product analytics is on." : "Product analytics is off."}`;
    analyticsState.textContent =
      analytics.checked === analyticsWasOn
        ? analyticsWasOn
          ? "On"
          : "Off"
        : analytics.checked
          ? "Will turn on"
          : "Will turn off";
    previewSlot.replaceChildren(phonePreview(readStatus()));
  };

  async function send(status) {
    save.disabled = true;
    try {
      await api("/status", { method: "PUT", body: { status, expectedVersion: current.version } });
      toast(
        status.maintenance.active
          ? "Saved. Maintenance is on."
          : analyticsOn(status)
            ? "Saved."
            : "Saved. Product analytics is off.",
      );
      route();
    } catch (err) {
      save.disabled = false;
      if (err.status === 409) {
        statusNotice = `Someone else changed the status while you were editing (now v${err.body?.current ?? "?"}). Check it and make your change again.`;
        toast("Someone else changed the status. Showing the latest.", "warn");
        route();
        return;
      }
      msg.textContent =
        err.status === 400
          ? err.body?.message || "The server rejected this status."
          : errorText(err);
      msg.focus();
    }
  }

  const form = h(
    "form",
    {
      class: "form status-main",
      novalidate: true,
      "aria-label": "Service status",
      oninput: refresh,
      onsubmit: async (e) => {
        e.preventDefault();
        msg.replaceChildren();
        msgKey.required = Boolean(msgText.value.trim());
        noticeKey.required = Boolean(noticeText.value.trim());
        if (!form.reportValidity()) return;
        const status = readStatus();
        const diff = diffView(st, status);
        const maintenanceChanged = status.maintenance.active !== m.active;
        const analyticsOff = analyticsWasOn && !analyticsOn(status);
        if (maintenanceChanged || analyticsOff) {
          const turnOn = maintenanceChanged && status.maintenance.active;
          const turnOff = maintenanceChanged && !status.maintenance.active;
          const ok = await confirmDialog({
            title: [
              turnOn && "Turn maintenance on for everyone",
              turnOff && "Turn maintenance off",
              analyticsOff && "turn product analytics off",
            ]
              .filter(Boolean)
              .join(" and ")
              .replace(/^./, (c) => c.toUpperCase())
              .concat("?"),
            body: [
              turnOn &&
                h("p", {
                  text: "Every write is refused for all users until you turn it off. Apps show the maintenance screen within about a minute.",
                }),
              turnOff && h("p", { text: "Apps go back to normal within about a minute." }),
              analyticsOff &&
                h("p", {
                  text: "Apps stop reporting events and drop what they hold; the server drops what still arrives. The “In the app” counts stop until you turn it back on.",
                }),
              diff && h("div", { style: { "margin-top": "12px" } }, diff),
            ].filter(Boolean),
            confirm:
              maintenanceChanged && analyticsOff
                ? "Save both"
                : turnOn
                  ? "Turn maintenance on"
                  : turnOff
                    ? "Turn it off"
                    : "Turn analytics off",
            danger: turnOn || analyticsOff,
          });
          if (!ok) return;
        }
        send(status);
      },
    },
    h(
      "div",
      { class: "status-now" },
      h("div", null, stateTitle, stateSub),
      h("label", { class: "switch" }, h("span", { class: "sr-only", text: "Maintenance" }), active),
    ),
    h("p", { class: "sr-only", id: "switch-hint", text: "Takes effect when you save." }),
    h(
      "fieldset",
      null,
      h("legend", { text: "Maintenance screen" }),
      field("Message", msgText, "Shown when the app has no string for the key. Blank sends none."),
      h(
        "div",
        { class: "row" },
        field("Message key", msgKey, "Names a string the app may carry."),
        field(
          "Back around (your time)",
          h("div", { class: "inline" }, until, clearUntil),
          null,
          until,
        ),
      ),
      untilHint,
    ),
    h(
      "fieldset",
      null,
      h("legend", { text: "Minimum build" }),
      field(
        "Oldest build that may run",
        minV,
        "Like 1.2 or 1.2.0+14. Older apps show “Update billet” and nothing else. Blank means no minimum.",
      ),
    ),
    h(
      "fieldset",
      null,
      h("legend", { text: "Notice" }),
      field(
        "Notice text",
        noticeText,
        "A soft line apps show until it's dismissed. Blank removes it.",
      ),
      field("Notice key", noticeKey),
    ),
    h(
      "fieldset",
      null,
      h("legend", { text: "Product analytics" }),
      h(
        "div",
        { class: "analytics-row" },
        h(
          "div",
          null,
          h("b", { text: "Apps report what people do in the app " }),
          analyticsState,
          h("p", {
            class: "hint",
            id: "analytics-hint",
            text: "Off: apps stop reporting events and drop what they hold; the server drops what still arrives.",
          }),
        ),
        h(
          "label",
          { class: "switch calm" },
          h("span", { class: "sr-only", text: "Product analytics" }),
          analytics,
        ),
      ),
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
      h(
        "p",
        { class: "hint" },
        current.version
          ? [
              `v${current.version} · `,
              ago(current.updatedAt),
              ` by ${current.updatedBy || "unknown"} · reaches apps in about a minute`,
            ]
          : "Never set: apps get the normal status.",
      ),
    ),
  );
  card.append(form, previewSlot);
  refresh();

  const prevOf = (i) => changes[i + 1]?.status ?? (changes[i].version === 1 ? NORMAL_STATUS : null);
  const history = dataTable({
    caption: "Status changes, newest first",
    noun: "changes",
    rows: changes.map((c, i) => ({ ...c, summary: statusSummary(c.status, prevOf(i)) })),
    sort: [0, "desc"],
    search: (c) => `${c.by} ${c.summary}`,
    columns: [
      { label: "When", value: (c) => c.at, cell: (c) => ago(c.at) },
      { label: "Version", num: true, value: (c) => c.version, cell: (c) => `v${c.version}` },
      { label: "Who", value: (c) => c.by },
      { label: "Change", cell: (c) => c.summary },
    ],
    none: empty("No changes yet", "Every save is kept here with who made it."),
  });

  return [
    pageHead(
      "Maintenance",
      "What every app is told: maintenance, the oldest build allowed to run, and a notice. Works while D1 is down.",
      [
        m.active ? pill("bad", "maintenance on") : pill("good", "normal"),
        analyticsWasOn ? null : pill("warn", "analytics off"),
      ],
    ),
    notice,
    card,
    section("History", null, history),
  ];
}

/* ---------- Audit log ---------- */

async function renderAudit() {
  const [{ changes: flagChanges }, { changes: statusChanges }] = await Promise.all([
    api("/history?limit=500"),
    api("/status/history?limit=200"),
  ]);
  const rows = mergeAudit(flagChanges, statusChanges);
  const hrefOf = (r) => (r.area === "maintenance" ? "#/maintenance" : `#/flags/${enc(r.subject)}`);
  return [
    pageHead("Audit log", "Every change made in this panel, with the Access email that made it."),
    dataTable({
      caption: "All changes",
      noun: "changes",
      rows,
      sort: [0, "desc"],
      href: hrefOf,
      search: (r) => `${r.by} ${r.subject} ${r.action} ${r.area} ${r.change.pairId || ""}`,
      filters: {
        label: "Area",
        options: [
          ["all", "All"],
          ["flag", "Flags"],
          ["pair", "Pair overrides"],
          ["maintenance", "Maintenance"],
        ],
        test: (r, f) => f === "all" || r.area === f,
      },
      columns: [
        { label: "When", value: (r) => r.at, cell: (r) => ago(r.at) },
        { label: "Who", value: (r) => r.by },
        { label: "Area", value: (r) => r.area, cell: (r) => pill("", r.area, true) },
        {
          label: "What",
          value: (r) => r.subject,
          cell: (r) => h("a", { class: "lead mono", href: hrefOf(r), text: r.subject }),
        },
        {
          label: "Change",
          cell: (r) =>
            r.area === "maintenance"
              ? statusSummary(
                  r.change.status,
                  r.previous ?? (r.change.version === 1 ? NORMAL_STATUS : null),
                )
              : [
                  pill("", r.action, true),
                  r.change.pairId
                    ? h("span", { class: "mono", text: ` pair ${r.change.pairId}` })
                    : null,
                  " ",
                  h("span", {
                    class: "sub",
                    style: { display: "inline" },
                    text: diffConfig(r.change.before, r.change.after)
                      .map((d) => d.path)
                      .join(", "),
                  }),
                ],
        },
      ],
      none: empty(
        "Nothing changed yet",
        "Saves, starts, stops, kills, overrides and status changes are listed here.",
      ),
    }),
  ];
}

/* ---------- Purchases ---------- */

const PURCHASE_TONE = { credited: "good", refunded: "warn" };
const signed = (n) => (n > 0 ? `+${n}` : String(n));
const packName = (productId) => productId.replace(/^com\.mikitahimpel\.billet\./, "");

async function renderPurchases() {
  const { purchases, ledger, notifications } = await api("/purchases?limit=500");
  const flagged = purchases.filter((p) => p.flagged).length;
  const refunded = purchases.filter((p) => p.status === "refunded").length;
  const ownerCell = (owner) =>
    owner.startsWith("demo:")
      ? h("span", { class: "mono", text: owner })
      : h("a", { class: "mono", href: `#/pairs/${enc(owner)}`, text: owner });

  return [
    pageHead(
      "Purchases",
      "Stamp packs bought through the App Store, and on dev the mock ones. Read-only: refunds come from Apple.",
    ),
    h(
      "div",
      { class: "stats" },
      statCard({ label: "Purchases", value: fmtNum(purchases.length, 0), foot: "newest 500" }),
      statCard({ label: "Refunded", value: fmtNum(refunded, 0) }),
      statCard({
        label: "Flagged",
        value: fmtNum(flagged, 0),
        foot: "a refund took back less than the pack",
      }),
    ),
    flagged > 0 &&
      callout(
        "warn",
        `${flagged} flagged ${flagged === 1 ? "purchase" : "purchases"}`,
        "The pair had fewer stamps than the refund, so the balance stopped at 0. Check them by hand.",
      ),
    section(
      "Purchases",
      "One row per App Store original transaction; each is credited once.",
      dataTable({
        caption: "Purchases",
        noun: "purchases",
        rows: purchases,
        sort: [6, "desc"],
        search: (p) => `${p.ownerId} ${p.productId} ${p.originalTransactionId} ${p.environment}`,
        filters: {
          label: "Status",
          options: [
            ["all", "All"],
            ["credited", "Credited"],
            ["refunded", "Refunded"],
            ["flagged", "Flagged"],
          ],
          test: (p, f) => f === "all" || (f === "flagged" ? p.flagged : p.status === f),
        },
        columns: [
          { label: "Owner", value: (p) => p.ownerId, cell: (p) => ownerCell(p.ownerId) },
          {
            label: "Pack",
            value: (p) => p.productId,
            cell: (p) => h("span", { class: "mono", text: packName(p.productId) }),
          },
          { label: "Stamps", num: true, value: (p) => p.stamps },
          {
            label: "Environment",
            value: (p) => p.environment,
            cell: (p) => pill("", p.environment, true),
          },
          {
            label: "Status",
            value: (p) => p.status,
            cell: (p) => [
              pill(PURCHASE_TONE[p.status] || "", p.status),
              p.flagged ? [" ", pill("bad", "flagged")] : null,
            ],
          },
          {
            label: "Transaction",
            value: (p) => p.originalTransactionId,
            cell: (p) => h("span", { class: "mono", text: p.originalTransactionId }),
          },
          { label: "Bought", value: (p) => p.purchasedAt, cell: (p) => fmtWhen(p.purchasedAt) },
          { label: "Updated", value: (p) => p.updatedAt, cell: (p) => ago(p.updatedAt) },
        ],
        none: empty(
          "No purchases yet",
          "A pack bought in the app appears here once it is credited.",
        ),
      }),
    ),
    section(
      "Stamp ledger",
      "Every change to a balance, newest first. A balance is the sum of its entries.",
      dataTable({
        caption: "Stamp ledger",
        noun: "entries",
        rows: ledger,
        sort: [4, "desc"],
        search: (e) => `${e.ownerId} ${e.id} ${e.productId}`,
        columns: [
          { label: "Owner", value: (e) => e.ownerId, cell: (e) => ownerCell(e.ownerId) },
          {
            label: "Entry",
            value: (e) => e.id,
            cell: (e) => h("span", { class: "mono", text: e.id }),
          },
          { label: "Kind", value: (e) => e.kind, cell: (e) => pill("", e.kind, true) },
          { label: "Amount", num: true, value: (e) => e.amount, cell: (e) => signed(e.amount) },
          { label: "When", value: (e) => e.at, cell: (e) => fmtWhen(e.at) },
        ],
        none: empty("The ledger is empty"),
      }),
    ),
    section(
      "App Store notifications",
      "What Apple told the server, and what was done. Consumption requests are not answered yet.",
      dataTable({
        caption: "App Store notifications",
        noun: "notifications",
        rows: notifications,
        sort: [0, "desc"],
        search: (n) => `${n.type} ${n.subtype || ""} ${n.outcome} ${n.originalTransactionId || ""}`,
        columns: [
          { label: "Received", value: (n) => n.receivedAt, cell: (n) => fmtWhen(n.receivedAt) },
          {
            label: "Type",
            value: (n) => n.type,
            cell: (n) =>
              h("span", { class: "mono", text: n.subtype ? `${n.type} · ${n.subtype}` : n.type }),
          },
          { label: "Environment", value: (n) => n.environment || "" },
          {
            label: "Transaction",
            value: (n) => n.originalTransactionId || "",
            cell: (n) => h("span", { class: "mono", text: n.originalTransactionId || "—" }),
          },
          { label: "Outcome", value: (n) => n.outcome, cell: (n) => pill("", n.outcome, true) },
        ],
        none: empty("No notifications yet", "Apple sends them to /v1/appstore/notifications."),
      }),
    ),
  ];
}

/* ---------- Onboarding ---------- */

const KIND_LABEL = {
  Single: "one choice",
  Multi: "several choices",
  Range: "range",
  Text: "typed",
  OpenChoice: "one choice (app's list)",
};

/** One bar per option or value: how many picked it, and its share of the step's answers. */
function answerBars(label, rows, answered) {
  const top = Math.max(1, ...rows.map((r) => r.count));
  if (!rows.some((r) => r.count)) return empty("No picks yet");
  return h(
    "div",
    { class: "funnel", role: "table", "aria-label": label },
    h(
      "div",
      { role: "row", style: { display: "contents" } },
      h("span", { class: "funnel-head", role: "columnheader", text: "Answer" }),
      h("span", { class: "funnel-head bar", role: "columnheader", "aria-hidden": "true" }),
      h("span", { class: "funnel-head f-num", role: "columnheader", text: "Picked" }),
      h("span", { class: "funnel-head f-conv", role: "columnheader", text: "Of answers" }),
    ),
    rows.map((r) =>
      h(
        "div",
        { role: "row", style: { display: "contents" } },
        h("span", { class: "f-label", role: "rowheader", text: r.label }),
        h(
          "span",
          { class: "f-track", "aria-hidden": "true" },
          h("span", {
            class: "f-fill",
            style: { "--w": `${((r.count / top) * 100).toFixed(1)}%` },
          }),
        ),
        h("span", { class: "f-num", role: "cell", text: fmtNum(r.count, 0) }),
        h("span", {
          class: "f-conv",
          role: "cell",
          text: answered === 0 ? "—" : fmtPct(r.count / answered),
        }),
      ),
    ),
  );
}

async function renderOnboarding() {
  const { version, accounts, steps, retired } = await api("/onboarding");
  const answered = steps.reduce((a, st) => a + st.answered, 0);
  const skipped = steps.reduce((a, st) => a + st.skipped, 0);
  const picks = (st) =>
    st.kind === "Range"
      ? st.values.map((v) => ({ label: String(v.value), count: v.count }))
      : st.options;

  return [
    pageHead(
      "Onboarding",
      "How each onboarding step was answered or skipped. Typed answers (names) are never shown here.",
    ),
    h(
      "div",
      { class: "stats" },
      statCard({ label: "Accounts", value: fmtNum(accounts, 0), foot: "with an answer or a skip" }),
      statCard({
        label: "Skip rate",
        value: answered + skipped === 0 ? "—" : fmtPct(skipped / (answered + skipped)),
        foot: "all steps",
      }),
      statCard({ label: "Questions", value: version, foot: "version served" }),
    ),
    section(
      "Steps",
      "Served questions in order, then the steps the app draws itself.",
      dataTable({
        caption: "Steps",
        noun: "steps",
        rows: steps,
        columns: [
          {
            label: "Step",
            value: (st) => st.id,
            cell: (st) => [
              h("span", { class: "mono", text: st.id }),
              st.native ? [" ", pill("", "in the app", true)] : null,
            ],
          },
          { label: "Question", value: (st) => st.title },
          { label: "Kind", value: (st) => KIND_LABEL[st.kind] || st.kind },
          { label: "Answered", num: true, value: (st) => st.answered },
          { label: "Skipped", num: true, value: (st) => st.skipped },
          {
            label: "Skip rate",
            num: true,
            value: (st) => st.skipRate ?? -1,
            cell: (st) => (st.skipRate == null ? "—" : fmtPct(st.skipRate)),
          },
        ],
        none: empty("No steps"),
      }),
    ),
    steps
      .filter((st) => st.kind !== "Text")
      .map((st) =>
        section(
          st.title,
          `${fmtNum(st.answered, 0)} answered · ${fmtNum(st.skipped, 0)} skipped${
            st.kind === "Multi" ? " · one answer can pick several" : ""
          }`,
          answerBars(st.title, picks(st), st.answered),
        ),
      ),
    retired.length > 0 &&
      section(
        "Retired steps",
        "Answers to steps the questions no longer have.",
        dataTable({
          caption: "Retired steps",
          noun: "steps",
          rows: retired,
          columns: [
            {
              label: "Step",
              value: (r) => r.stepId,
              cell: (r) => h("span", { class: "mono", text: r.stepId }),
            },
            { label: "Answers", num: true, value: (r) => r.count },
          ],
        }),
      ),
  ];
}

/* ---------- Retention ---------- */

const RETENTION_MODES = [
  ["both", "Both active", "Both partners opened the app or sent a note on day N."],
  ["either", "Either active", "At least one partner opened the app or sent a note on day N."],
  ["bothNote", "Both sent a note", "Both partners sent a note on day N: the north star at day 7."],
];

/** `#/retention/<mode>/<key=variant or ->/<build or ->`. */
const retentionHref = (mode, variant, version) =>
  `#/retention/${mode}/${enc(variant || "-")}/${enc(version || "-")}`;

function retentionCell(cell, max) {
  if (cell.state === "pending")
    return h(
      "td",
      { class: "heat pending", title: "No pair of this week has reached this day yet" },
      "",
    );
  if (cell.state === "too-few")
    return h(
      "td",
      { class: "heat few", title: "Fewer than 5 pairs: no number is shown" },
      "too few",
    );
  const level = max > 0 ? cell.share / max : 0;
  return h(
    "td",
    {
      class: `heat${level > 0.6 ? " hot" : ""}${cell.partial ? " partial" : ""}`,
      style: { "--heat": level.toFixed(3) },
      title: `${cell.count} of ${cell.of} pairs · 95% interval ${fmtPct(cell.low, 0)}–${fmtPct(cell.high, 0)}${
        cell.partial ? " · some pairs of this week are still too young" : ""
      }`,
    },
    fmtPct(cell.share, 0),
  );
}

async function renderRetention([modeArg, variantArg, versionArg]) {
  const mode = RETENTION_MODES.some(([m]) => m === modeArg) ? modeArg : "both";
  const variant = variantArg && variantArg !== "-" ? variantArg : "";
  const version = versionArg && versionArg !== "-" ? versionArg : "";
  const query = new URLSearchParams();
  if (variant) query.set("variant", variant);
  if (version) query.set("version", version);
  const grid = await api(`/retention${query.size ? `?${query}` : ""}`);
  const [, modeLabel, modeHelp] = RETENTION_MODES.find(([m]) => m === mode);

  const values = grid.rows.flatMap((row) =>
    row.cells[mode].filter((c) => c.state === "value").map((c) => c.share),
  );
  const max = values.length ? Math.max(...values) : 0;

  const modePicker = h(
    "nav",
    { class: "seg", "aria-label": "What counts as retained" },
    RETENTION_MODES.map(([m, label]) =>
      h("a", {
        href: retentionHref(m, variant, version),
        "aria-current": m === mode ? "true" : null,
        text: label,
      }),
    ),
  );
  const filter = (label, value, options, toHref) => {
    const id = fid();
    return h(
      "label",
      { class: "inline-field", for: id },
      h("span", { text: label }),
      h(
        "select",
        { id, onchange: (e) => (location.hash = toHref(e.target.value)) },
        h("option", { value: "", text: "All", selected: !value }),
        options.map(([v, text]) => h("option", { value: v, text, selected: v === value })),
      ),
    );
  };
  const filters = h(
    "div",
    { class: "filters" },
    filter(
      "Variant",
      variant,
      grid.options.variants.map(({ key, variant: v }) => [`${key}=${v}`, `${key}: ${v}`]),
      (v) => retentionHref(mode, v, version),
    ),
    filter(
      "Build when paired",
      version,
      grid.options.appVersions.map((v) => [v, v === "unknown" ? "unknown (no report)" : v]),
      (v) => retentionHref(mode, variant, v),
    ),
  );

  const table = h(
    "div",
    { class: "box table-wrap" },
    h(
      "table",
      { class: "retention" },
      h("caption", { class: "sr-only", text: `Retention by week paired: ${modeLabel}` }),
      h(
        "thead",
        null,
        h(
          "tr",
          null,
          h("th", { scope: "col", text: "Week paired" }),
          h("th", { scope: "col", class: "num", text: "Pairs" }),
          grid.days.map((d) => h("th", { scope: "col", class: "num", text: `Day ${d}` })),
        ),
      ),
      h(
        "tbody",
        null,
        grid.rows.map((row) =>
          h(
            "tr",
            { class: row.week === "all" ? "total" : null },
            h("th", {
              scope: "row",
              text: row.week === "all" ? "All weeks" : `${fmtDay(row.week)} week`,
            }),
            h("td", { class: "num", text: row.pairs == null ? "too few" : fmtNum(row.pairs, 0) }),
            row.cells[mode].map((cell) => retentionCell(cell, max)),
          ),
        ),
      ),
    ),
  );

  const anyPairs = grid.rows.some((row) => row.pairs != null);
  return [
    pageHead(
      "Retention",
      "Pairs by the week they formed (UTC, from Monday), and the share retained N days after. Day 0 is the day they paired.",
      modePicker,
    ),
    filters,
    anyPairs
      ? section(
          modeLabel,
          modeHelp,
          table,
          h(
            "p",
            { class: "heat-legend" },
            h("span", { class: "key heat-key" }),
            "stronger colour is a higher share, within this view",
            h("span", { class: "key pending-key" }),
            "not reached yet",
            h("span", { class: "key few-key" }),
            "under 5 pairs: too few",
            h("i", { text: "Italic" }),
            "some pairs of the week are still too young; hover a cell for its count and 95% interval",
          ),
        )
      : empty(
          "Not enough pairs yet",
          "A row appears once 5 pairs formed in a week" +
            (variant || version ? " under these filters." : "."),
        ),
  ];
}

/* ---------- Router ---------- */

const ROUTES = {
  overview: renderOverview,
  events: renderEvents,
  retention: renderRetention,
  experiments: renderExperiments,
  flags: renderFlags,
  pairs: renderPairs,
  maintenance: renderMaintenance,
  purchases: renderPurchases,
  onboarding: renderOnboarding,
  audit: renderAudit,
};
const updatedEl = document.getElementById("updated");
let loadedAt = 0;
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
      main.replaceChildren(h("p", { class: "empty loading", role: "status", text: "Loading…" })),
    150,
  );
  let nodes;
  try {
    nodes = await ROUTES[name](args);
  } catch (err) {
    nodes = [
      pageHead(err.status === 403 ? "Not authorised" : "Couldn't load this page"),
      callout("bad", errorText(err), null),
      h(
        "div",
        { class: "actions", style: { "margin-top": "16px" } },
        h("button", { type: "button", class: "btn", text: "Try again", onclick: () => route() }),
      ),
    ];
  }
  clearTimeout(busy);
  if (seq !== renderSeq) return;
  main.replaceChildren(h("div", { class: "enter" }, nodes));
  loadedAt = Date.now();
  tick();
  document.title = `${main.querySelector("h1")?.textContent || "billet"} · billet admin`;
  if (!firstRender) main.querySelector("h1")?.focus({ preventScroll: false });
  firstRender = false;
}

document.getElementById("skip").addEventListener("click", (e) => {
  e.preventDefault();
  main.focus();
});
document.getElementById("refresh").addEventListener("click", () => route());
setInterval(tick, 30_000);

window.addEventListener("hashchange", route);
api("/me").then(
  (me) => {
    document.getElementById("me-email").textContent = me.email;
    const env = document.getElementById("env");
    env.textContent = me.environment || "unknown";
    env.dataset.env = me.environment || "";
    env.setAttribute("aria-label", `Environment: ${me.environment || "unknown"}`);
  },
  (err) => {
    document.getElementById("me-email").textContent =
      err.status === 403
        ? "Not authorised through Cloudflare Access"
        : "Signed-in email unavailable";
  },
);
route();
