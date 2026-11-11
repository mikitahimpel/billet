#!/usr/bin/env python3
"""Seeds a Simulator's app group with the couple, coins and lists the screenshots show.

Usage: seed.py <simulator udid>   (the app must be installed and terminated)
The Moments photos in moments/ were generated with Codex CLI; nobody in them is real.
Dates are Foundation reference-date seconds, as SharedFile writes them.
"""
import json, subprocess, sys, uuid, datetime, pathlib

udid = sys.argv[1]
group = subprocess.check_output(
    ["xcrun", "simctl", "get_app_container", udid, "com.ourio.app", "group.com.ourio.app"], text=True
).strip()
root = pathlib.Path(group)

REF = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)
now = datetime.datetime.now(datetime.timezone.utc)
today = datetime.datetime.combine(datetime.date.today(), datetime.time()).astimezone()


def ref(d: datetime.datetime) -> float:
    return (d - REF).total_seconds()


def write(path: str, value) -> None:
    p = root / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(value))


def item(text, author, mins_ago, **extra):
    return {
        "id": str(uuid.uuid4()).upper(), "text": text, "author": author,
        "added": ref(now - datetime.timedelta(minutes=mins_ago)), "place": False,
        "moments": [], "wants": [], **extra,
    }


def lst(kind, title, symbol, tint, items):
    return {"id": str(uuid.uuid4()).upper(), "kind": kind, "title": title,
            "icon": {"symbol": symbol, "tint": tint}, "items": items}


write("Couple/couple.json", {
    "partners": ["L", "M"], "viewer": "L", "names": {"L": "Lily", "M": "Max"},
    "togetherSince": ref(today - datetime.timedelta(days=1021)),
})
write("Us/streak.json", {"count": 47, "best": 47, "lastDay": ref(today)})
write("Shop/wallet.json", {
    "coins": 1240, "level": 4, "progress": 0.62,
    "owned": ["lamp", "rug"], "wishlist": [], "gifted": [],
})

done = lambda m: ref(now - datetime.timedelta(minutes=m))
groceries = [
    item("Avocados", "M", 50, aisle="produce", quantity="3"),
    item("Strawberries", "L", 40, aisle="produce"),
    item("Baby spinach", "M", 38, aisle="produce", done=done(4), doneBy="L"),
    item("Oat milk", "L", 90, aisle="dairy", quantity="2"),
    item("Greek yogurt", "M", 33, aisle="dairy"),
    item("Sourdough", "L", 30, aisle="bakery", done=done(6), doneBy="L"),
    item("Croissants", "M", 20, aisle="bakery", quantity="4"),
    item("Salmon fillets", "L", 25, aisle="meat"),
    item("Coffee beans", "M", 15, aisle="pantry"),
    item("Pasta", "L", 12, aisle="pantry"),
    item("Cat treats for Mochi", "M", 8, aisle="pet"),
]


def film(text, author, mins):
    return item(text, author, mins, wants=["L", "M"] if mins % 2 == 0 else [author])


# Made-up titles: the grid draws its own gradient tiles, and compose-watch.py lays the
# generated posters in posters/ over them, in this order.
watch = [
    film("Paper Moons", "L", 300), film("Midnight Bakery", "M", 281),
    film("Pip & the Lighthouse", "L", 200), film("Room 404", "M", 150),
    film("Before the Rain", "L", 101), film("Lisbon Tram", "M", 90),
    film("Hotel Marzipan", "L", 70), film("Cherry Season", "M", 51),
    film("Starlight Drive-In", "L", 30),
]
travel = [
    item("Japan", "L", 900, country="JP"), item("Lisbon", "M", 800, country="PT", place=True),
    item("Iceland", "L", 700, country="IS"), item("New Orleans", "M", 600, country="US", place=True),
    item("Mexico City", "L", 500, country="MX", place=True), item("Amalfi Coast", "M", 450, country="IT", place=True),
    item("Bali", "L", 400, country="ID"), item("Banff", "M", 350, country="CA", place=True),
    item("France", "L", 2000, country="FR", done=done(60 * 24 * 200), doneBy="M", visitedIn="2026-04"),
    item("Greece", "M", 3000, country="GR", done=done(60 * 24 * 400), doneBy="L", visitedIn="2025-08"),
    item("Spain", "L", 3500, country="ES", done=done(60 * 24 * 500), doneBy="L", visitedIn="2025-05"),
    item("Croatia", "M", 4000, country="HR", done=done(60 * 24 * 600), doneBy="M", visitedIn="2024-09"),
    item("United Kingdom", "L", 4500, country="GB", done=done(60 * 24 * 700), doneBy="L", visitedIn="2024-04"),
    item("Canada", "M", 5000, country="CA", done=done(60 * 24 * 800), doneBy="M", visitedIn="2023-12"),
    item("Thailand", "L", 5500, country="TH", done=done(60 * 24 * 900), doneBy="L", visitedIn="2023-08"),
]
write("Us/us.json", {
    "lists": [
        lst("groceries", "Groceries", "basket.fill", "sage", groceries),
        lst("watch", "To watch", "popcorn.fill", "coral", watch),
        lst("travel", "Places to go", "airplane", "sky", travel),
    ],
    "wishes": [
        {"id": str(uuid.uuid4()).upper(), "owner": o, "title": t, "link": "", "price": pr, "note": "",
         "mostWanted": mw, "added": ref(now - datetime.timedelta(days=d)), "rewarded": False}
        for o, t, pr, mw, d in [("L", "Film camera", "$120", True, 3), ("M", "Running shoes", "$95", False, 5),
                                ("L", "Pottery class for two", "$80", False, 9)]
    ], "loves": {}, "events": [], "planned": [], "swipes": {},
})
here = pathlib.Path(__file__).parent
moments = [
    ("coffee", "L", 0.1, "Sunday coffee ☕️", True), ("cat", "M", 1, "Mochi’s twin?", False),
    ("ramen", "M", 6, "Best ramen of the trip", True), ("hike", "L", 12, "We made it to the top!", False),
    ("picnic", "L", 20, "", True), ("beach", "M", 34, "Last sunset of summer", False),
]
index = []
for name, author, days, caption, loved in moments:
    file = f"{uuid.uuid4()}.jpg".upper()
    (root / "Moments").mkdir(parents=True, exist_ok=True)
    (root / "Moments" / file).write_bytes((here / "moments" / f"{name}.jpg").read_bytes())
    index.append({"id": str(uuid.uuid4()).upper(), "author": author, "caption": caption, "file": file,
                  "date": ref(now - datetime.timedelta(days=days)), "pinned": name in ("hike", "coffee", "beach", "picnic"), "loved": loved})
write("Moments/moments.json", index)
print("seeded", root)
