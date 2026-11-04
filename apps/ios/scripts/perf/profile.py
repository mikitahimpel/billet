"""Totals a Time Profiler export by symbol: self and inclusive samples, per thread kind.

    xcrun xctrace export --input x.trace \
      --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' > x.xml
    python3 -I profile.py x.xml [--thread main] [--top 40] [--match Billet]
"""

import argparse
import collections
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("xml")
    parser.add_argument("--thread", default="main")
    parser.add_argument("--top", type=int, default=40)
    parser.add_argument("--match", default="")
    args = parser.parse_args()
    ids = {}
    selfs = collections.Counter()
    inclusive = collections.Counter()
    threads = collections.Counter()
    total = 0
    for _, row in ET.iterparse(args.xml):
        if row.tag != "row":
            continue
        for element in row.iter():
            if "id" in element.attrib:
                ids[element.attrib["id"]] = element
        thread = row.find("thread")
        if thread is not None and "ref" in thread.attrib:
            thread = ids.get(thread.attrib["ref"], thread)
        name = thread.attrib.get("fmt", "") if thread is not None else ""
        threads[name.split(" (")[0][:60]] += 1
        if args.thread == "main" and "Main Thread" not in name:
            row.clear()
            continue
        backtrace = row.find("backtrace")
        if backtrace is not None and "ref" in backtrace.attrib:
            backtrace = ids.get(backtrace.attrib["ref"], backtrace)
        if backtrace is None:
            continue
        frames = []
        for frame in backtrace.findall("frame"):
            if "ref" in frame.attrib:
                frame = ids.get(frame.attrib["ref"], frame)
            frames.append(frame.attrib.get("name", "?"))
        if not frames:
            continue
        total += 1
        selfs[frames[0]] += 1
        for symbol in set(frames):
            inclusive[symbol] += 1
    print(f"samples on {args.thread}: {total}")
    print("threads:", ", ".join(f"{n} {c}" for n, c in threads.most_common(8)))
    print("\n## self")
    for symbol, count in selfs.most_common(args.top):
        print(f"{100 * count / max(total, 1):5.1f}% {symbol[:140]}")
    print("\n## inclusive" + (f" matching {args.match}" if args.match else ""))
    shown = 0
    for symbol, count in inclusive.most_common():
        if args.match and args.match not in symbol:
            continue
        print(f"{100 * count / max(total, 1):5.1f}% {symbol[:140]}")
        shown += 1
        if shown >= args.top:
            break


if __name__ == "__main__":
    main()
