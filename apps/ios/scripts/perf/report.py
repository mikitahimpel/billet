"""Summarises one measure.sh run directory as Markdown: medians and ranges of every PERF line.

    python3 -I report.py <run dir>            # one run
    python3 -I report.py <base dir> <new dir> # side by side, with the ratio base / new
"""

import re
import statistics
import sys
from pathlib import Path

LINE = re.compile(r"^PERF (\w+) ?(\S*)\s*(.*)$")


def pairs(text):
    return {k: v for k, v in (p.split("=", 1) for p in text.split() if "=" in p)}


def number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def parse(log):
    found = {"marks": {}, "phases": {}, "timings": {}, "census": {}, "memory": None, "done": False}
    for raw in log.read_text(errors="replace").splitlines():
        match = LINE.match(raw.strip())
        if not match:
            continue
        kind, name, rest = match.groups()
        if kind == "mark":
            found["marks"].setdefault(name, number(pairs(rest).get("t")))
        elif kind == "phase":
            found["phases"][name] = pairs(rest)
        elif kind == "timing":
            found["timings"].setdefault(name, []).append(pairs(rest))
        elif kind == "census":
            values = pairs(name + " " + rest)
            found["census"].setdefault(values.get("scene", "?"), values)
        elif kind == "memory":
            found["memory"] = number(pairs(name + " " + rest).get("peakMB"))
        elif kind == "done":
            found["done"] = True
    return found


def first_room(marks):
    rooms = [t for name, t in marks.items() if name.endswith("room_on_screen") and t is not None]
    return min(rooms) if rooms else None


def collect(run_dir):
    """Every metric of a run directory, as name -> list of samples."""
    metrics = {}

    def add(name, value):
        if value is not None:
            metrics.setdefault(name, []).append(value)

    launches = sorted(run_dir.glob("launch-*.log"))
    fulls = sorted(run_dir.glob("full-*.log"))
    costs = sorted(run_dir.glob("cost-*.log"))
    for log in launches + fulls + costs:
        run = parse(log)
        if not run["done"]:
            add("failed runs", 1)
            continue
        kind = log.name.split("-")[0]
        if kind == "launch":
            add("launch: process start to first frame (ms)", run["marks"].get("first_frame"))
            add("launch: process start to Home room drawing (ms)", first_room(run["marks"]))
            # The stages between, in the order a launch reaches them.
            for stage in ("app_built", "root_built", "shell_shown", "home_shown"):
                add(f"launch: process start to {stage.replace('_', ' ')} (ms)", run["marks"].get(stage))
            add("launch: memory peak (MB)", run["memory"])
        else:
            add(f"{kind}: memory peak (MB)", run["memory"])
        for phase, values in run["phases"].items():
            if kind == "launch" and phase != "idle":
                continue
            for key in ("p50", "p95", "p99", "max", "hitches", "mainCPU", "procCPU", "fps", "slow",
                        "slowMs", "slowBusyMs"):
                add(f"{kind}.{phase}: {key}", number(values.get(key)))
        for timing, samples in run["timings"].items():
            for values in samples:
                add(f"switch {timing}: ms", number(values.get("ms")))
                add(f"switch {timing}: worst frame (ms)", number(values.get("max")))
                add(f"switch {timing}: memory after (MB)", number(values.get("mb")))
        for scene, values in run["census"].items():
            for key, value in values.items():
                if key not in ("scene", "heaviest"):
                    add(f"scene {scene}: {key}", number(value))
    size = run_dir / "app-kb.txt"
    if size.exists():
        add("app (Simulator build, KB)", number(size.read_text().strip()))
    return metrics


def breakdown(metrics):
    """What each part a cost run switched off was worth: frame time with it and without it."""
    rows = []
    parts = []
    for name in metrics:
        if name.startswith("cost.cost.") and name.endswith(".on.orbit: p50"):
            parts.append(name[len("cost.cost."):-len(".on.orbit: p50")])
    for part in parts:
        for motion in ("still", "orbit"):
            for key in ("p50", "p95", "fps"):
                on = metrics.get(f"cost.cost.{part}.on.{motion}: {key}")
                off = metrics.get(f"cost.cost.{part}.off.{motion}: {key}")
                if on and off:
                    a, b = statistics.median(on), statistics.median(off)
                    rows.append(f"| {part} | {motion} {key} | {show(on)} | {show(off)} | {a - b:+.2f} |")
    if rows:
        print("\n## What each part costs\n")
        print("Each part off and back on, back to back in one launch. A positive difference in")
        print("p50/p95 (ms) is what the part costs per frame; a negative one in fps is what it takes away.\n")
        print("| Part | Metric | With it | Without it | Difference |\n|---|---|---|---|---|")
        print("\n".join(rows))


def show(samples):
    if not samples:
        return "-"
    middle = statistics.median(samples)
    if len(samples) == 1 or min(samples) == max(samples):
        return f"{middle:g}"
    return f"{middle:g} ({min(samples):g}-{max(samples):g})"


def main(args):
    runs = [Path(a) for a in args]
    collected = [collect(r) for r in runs]
    names = []
    for metrics in collected:
        names += [n for n in metrics if n not in names]
    print(f"# Perf run: {' vs '.join(r.name for r in runs)}\n")
    for run in runs:
        load = run / "load.txt"
        if load.exists():
            print(f"- {run.name} load: {' / '.join(load.read_text().split(chr(10))[:2])}")
    print()
    header = " | ".join(r.name for r in runs)
    if len(runs) == 2:
        print(f"| Metric | {header} | Ratio |\n|---|---|---|---|")
    else:
        print(f"| Metric | {header} |\n|---|---|")
    for name in names:
        cells = [show(m.get(name, [])) for m in collected]
        if len(runs) == 2:
            a, b = (collected[0].get(name), collected[1].get(name))
            ratio = "-"
            if a and b and statistics.median(b) > 0:
                ratio = f"{statistics.median(a) / statistics.median(b):.2f}x"
            print(f"| {name} | {cells[0]} | {cells[1]} | {ratio} |")
        else:
            print(f"| {name} | {' | '.join(cells)} |")
    if len(runs) == 1:
        breakdown(collected[0])


if __name__ == "__main__":
    main(sys.argv[1:])
