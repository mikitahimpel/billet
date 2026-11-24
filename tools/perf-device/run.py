#!/usr/bin/env python3
"""One measuring run of Ourio on a phone on a cable: launch with a Labs arm, sample the battery, read the app's own
PERFLINE log, write <out>/<name>/{battery.csv,app.log,summary.json}. See README.md. No secrets are read or written."""
import argparse, csv, json, os, plistlib, re, signal, statistics, subprocess, sys, threading, time

IDEVICE = "/opt/homebrew/bin"
BUNDLE = "com.ourio.app"


def battery(udid):
    out = subprocess.run([f"{IDEVICE}/idevicediagnostics", "-u", udid, "ioregentry", "AppleSmartBattery"],
                         capture_output=True, timeout=30).stdout
    d = plistlib.loads(out)
    d = d.get("IORegistry", d)
    return {"temp_c": d["Temperature"] / 100, "virtual_temp_c": d.get("VirtualTemperature", 0) / 100,
            "amperage_ma": d["InstantAmperage"], "voltage_mv": d["Voltage"], "charging": d.get("IsCharging"),
            "external": d.get("ExternalConnected"), "level": d.get("CurrentCapacity")}


def sample_battery(udid, path, stop, every=10):
    started = time.time()
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["t", "temp_c", "virtual_temp_c", "amperage_ma", "voltage_mv", "charging", "external", "level"])
        while not stop.is_set():
            try:
                b = battery(udid)
                w.writerow([round(time.time() - started), b["temp_c"], b["virtual_temp_c"], b["amperage_ma"],
                            b["voltage_mv"], b["charging"], b["external"], b["level"]])
                f.flush()
            except Exception as e:  # a missed sample is a gap, not a failed run
                print("battery sample failed:", e, file=sys.stderr)
            stop.wait(every)


def cool_down(udid, target, limit):
    """Waits until the battery temperature is within 1 degree of `target`, at most `limit` seconds."""
    end = time.time() + limit
    while time.time() < end:
        t = battery(udid)["temp_c"]
        if t <= target + 1:
            return t
        print(f"cooling: {t:.1f} C, want <= {target + 1:.1f}", file=sys.stderr)
        time.sleep(20)
    return battery(udid)["temp_c"]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("name")
    p.add_argument("--udid", default=os.environ.get("PERF_UDID", ""))
    p.add_argument("--lab", default="tier=full", help='-perf.lab value, e.g. "noSunShadow,tier=full"')
    p.add_argument("--room", default="living", help="living or bedroom")
    p.add_argument("--seconds", type=int, default=180)
    p.add_argument("--warmup", type=int, default=30, help="seconds left out of the means")
    p.add_argument("--cool-to", type=float, help="battery temperature to cool down to before the run, in C")
    p.add_argument("--cool-limit", type=int, default=600)
    p.add_argument("--out", default=os.path.expanduser("~/Library/Caches/perf-device-runs"))
    p.add_argument("--extra", nargs="*", default=[], help="more launch arguments")
    a = p.parse_args()
    if not a.udid:
        sys.exit("pass --udid or set PERF_UDID (xcrun devicectl list devices)")
    out = os.path.join(a.out, a.name)
    os.makedirs(out, exist_ok=True)

    start_temp = cool_down(a.udid, a.cool_to, a.cool_limit) if a.cool_to else battery(a.udid)["temp_c"]
    stop = threading.Event()
    bt = threading.Thread(target=sample_battery, args=(a.udid, os.path.join(out, "battery.csv"), stop))
    bt.start()
    args = ["-perf.log", "1", "-perf.lab", a.lab, "-perf.room", a.room] + a.extra
    log = open(os.path.join(out, "app.log"), "w")
    # --console streams the app's stdout and stderr and ends the app when this process ends.
    proc = subprocess.Popen(["xcrun", "devicectl", "device", "process", "launch", "--console", "--terminate-existing",
                             "--device", a.udid, BUNDLE, *args], stdout=log, stderr=subprocess.STDOUT)
    time.sleep(a.seconds)
    proc.send_signal(signal.SIGINT)
    try:
        proc.wait(20)
    except subprocess.TimeoutExpired:
        proc.kill()
    stop.set()
    bt.join()
    log.close()
    summarize(out, a, start_temp)


def summarize(out, a, start_temp):
    lines = [l for l in open(os.path.join(out, "app.log"), errors="replace") if "PERFLINE" in l]
    cpus, heats, writes, room = [], set(), None, None
    for l in lines:
        t = int(re.search(r"t=(\d+)", l).group(1))
        m = re.search(r"CPU (\d+)%", l)
        if m and t >= a.warmup:
            cpus.append(int(m.group(1)))
        h = re.search(r"CPU \d+% . room \w+ . (nominal|fair|serious|critical)", l)
        if h:
            heats.add(h.group(1))
        w = re.search(r"scene writes/s[^·]*", l)
        if w:
            writes = w.group(0).strip()
        r = re.search(r"kind=.*|entities.*|triangles.*", l)
    rows = list(csv.DictReader(open(os.path.join(out, "battery.csv"))))
    temps = [float(r["temp_c"]) for r in rows]
    amps = [float(r["amperage_ma"]) for r in rows if int(r["t"]) >= a.warmup]
    summary = {
        "name": a.name, "lab": a.lab, "room": a.room, "seconds": a.seconds,
        "cpu_mean": round(statistics.mean(cpus), 1) if cpus else None,
        "cpu_max": max(cpus) if cpus else None,
        "temp_start_c": temps[0] if temps else None, "temp_end_c": temps[-1] if temps else None,
        "temp_delta_c": round(temps[-1] - temps[0], 2) if temps else None,
        "pre_cool_temp_c": start_temp,
        "amperage_ma_mean": round(statistics.mean(amps)) if amps else None,
        "thermal_states": sorted(heats), "scene_writes": writes, "perflines": len(lines),
        "last_line": lines[-1].strip() if lines else None,
    }
    json.dump(summary, open(os.path.join(out, "summary.json"), "w"), indent=2)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
