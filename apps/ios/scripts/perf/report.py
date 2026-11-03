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
    for log in launches + fulls:
        run = parse(log)
        if not run["done"]:
            add("failed runs", 1)
            continue
        kind = "launch" if log.name.startswith("launch") else "full"
        if kind == "launch":
            add("launch: process start to first frame (ms)", run["marks"].get("first_frame"))
            add("launch: process start to Home room drawing (ms)", first_room(run["marks"]))
            add("launch: memory peak (MB)", run["memory"])
        else:
            add("full: memory peak (MB)", run["memory"])
        for phase, values in run["phases"].items():
            if kind == "launch" and phase != "idle":
                continue
            for key in ("p50", "p95", "p99", "max", "hitches", "mainCPU", "procCPU", "fps"):
                add(f"{kind}.{phase}: {key}", number(values.get(key)))
        for timing, samples in run["timings"].items():
            for values in samples:
                add(f"switch {timing}: ms", number(values.get("ms")))
                add(f"switch {timing}: worst frame (ms)", number(values.get("max")))
        for scene, values in run["census"].items():
            for key, value in values.items():
                if key not in ("scene", "heaviest"):
                    add(f"scene {scene}: {key}", number(value))
    size = run_dir / "app-kb.txt"
    if size.exists():
        add("app (Simulator build, KB)", number(size.read_text().strip()))
    return metrics


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


if __name__ == "__main__":
    main(sys.argv[1:])
