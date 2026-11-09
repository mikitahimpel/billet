// Measures the PairRoom live-stroke relay end to end, each leg as excess over its fastest frame
// (the clocks are not in step). Creates real accounts, so dev Worker only unless `--host-ok`.
//   BILLET_HOST=<host> node scripts/live-latency.mjs [frames=150] [intervalMs=40] [--host-ok]
import { randomBytes } from "node:crypto";

const host = (process.env.BILLET_HOST ?? "").replace(/^https?:\/\//, "").replace(/\/$/, "");
if (!host) throw new Error("set BILLET_HOST to the API host");
const args = process.argv.slice(2);
if (!host.includes("billet-api-dev") && !args.includes("--host-ok"))
  throw new Error("BILLET_HOST is not the dev Worker; pass --host-ok only if that host is agreed");
const [framesArg = "150", intervalArg = "40"] = args.filter((arg) => arg !== "--host-ok");
const frames = Number(framesArg);
const interval = Number(intervalArg);
const base = `https://${host}`;

const call = async (method, path, token, body) => {
  const response = await fetch(base + path, {
    method,
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  if (!response.ok) throw new Error(`${method} ${path}: ${response.status}`);
  return response.status === 204 ? null : response.json();
};

const signIn = async () =>
  (
    await call("POST", "/v1/auth/anonymous", null, {
      accountKey: randomBytes(32).toString("base64url"),
    })
  ).sessionToken;

const open = (token) =>
  new Promise((resolve, reject) => {
    const socket = new WebSocket(`wss://${host}/v1/socket`, {
      headers: { authorization: `Bearer ${token}` },
    });
    socket.onopen = () => resolve(socket);
    socket.onerror = () => reject(new Error("socket failed to open"));
  });

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const quantiles = (values) => {
  const sorted = values.toSorted((x, y) => x - y);
  const at = (p) => sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
  const round = (x) => (x === undefined ? null : Math.round(x));
  return {
    n: sorted.length,
    p50: round(at(0.5)),
    p90: round(at(0.9)),
    p99: round(at(0.99)),
    max: round(sorted.at(-1)),
  };
};

const sender = await signIn();
const receiver = await signIn();
try {
  const { code } = await call("POST", "/v1/invites", sender);
  await call("POST", "/v1/invites/claim", receiver, { code });

  const out = await open(sender);
  const into = await open(receiver);
  // Index → send time, this machine's clock in ms.
  const sentAt = new Map();
  const arrivals = [];
  into.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message._tag !== "StrokePoints") return;
    const index = message.points[0]?.y;
    arrivals.push({ index, arrived: Date.now(), relayedAt: message.relayedAt });
  };

  await sleep(500);
  out.send(JSON.stringify({ _tag: "StrokeBegin", id: 1, color: "#7B4FE0", width: 0.032 }));
  for (let index = 0; index < frames; index += 1) {
    sentAt.set(index, Date.now());
    out.send(JSON.stringify({ _tag: "StrokePoints", id: 1, points: [{ x: 0.5, y: index }] }));
    await sleep(interval);
  }
  out.send(JSON.stringify({ _tag: "StrokeEnd", id: 1 }));
  await sleep(1500);
  out.close();
  into.close();

  const rows = arrivals
    .filter((row) => sentAt.has(row.index))
    .map((row) => ({
      ...row,
      total: row.arrived - sentAt.get(row.index),
      inbound: row.relayedAt === undefined ? undefined : row.relayedAt - sentAt.get(row.index),
      outbound: row.relayedAt === undefined ? undefined : row.arrived - row.relayedAt,
    }));
  const stamped = rows.filter((row) => row.inbound !== undefined);
  const fastestIn = Math.min(...stamped.map((row) => row.inbound));
  const fastestOut = Math.min(...stamped.map((row) => row.outbound));
  const late = rows.filter((row) => row.total > 150);
  const lateIn = late.filter((row) => row.inbound - fastestIn > row.outbound - fastestOut);

  console.log(
    JSON.stringify(
      {
        frames,
        intervalMs: interval,
        dropped: frames - rows.length,
        total: quantiles(rows.map((row) => row.total)),
        inboundExcess: quantiles(stamped.map((row) => row.inbound - fastestIn)),
        outboundExcess: quantiles(stamped.map((row) => row.outbound - fastestOut)),
        over150: {
          frames: late.length,
          mostlyInbound: lateIn.length,
          mostlyOutbound: late.length - lateIn.length,
        },
      },
      null,
      2,
    ),
  );
} finally {
  for (const token of [sender, receiver])
    await call("DELETE", "/v1/account", token, {}).catch((error) => {
      console.error(`account not deleted: ${error.message}`);
      process.exitCode = 1;
    });
}
