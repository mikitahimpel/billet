"""Writes diorama.json: manifest.py <info.json> <out.json> <width>."""
import json
import sys

info = json.load(open(sys.argv[1]))
width = int(sys.argv[3])
height = width * 11 // 20
margin = 0.0556
manifest = {
    "size": [width, height],
    "visible": {"x": margin, "y": margin, "width": 1 - 2 * margin, "height": 1 - 2 * margin},
    "times": ["day", "dusk", "night"],
    "layers": [
        {"name": "sky", "file": "sky_{time}.webp", "follow": 0.0},
        {"name": "far", "file": "far_{time}.webp", "follow": 0.2},
        {"name": "mid", "file": "mid_{time}.webp", "follow": 0.42},
        {"name": "street", "file": "street_{time}.webp", "follow": 0.62},
        {"name": "near", "file": "near_{time}.webp", "follow": 0.85},
    ],
    "cars": {
        "file": "cars_{time}.webp",
        "cells": 6,
        "faces": "right",
        "lanes": info["lanes"],
        "crossing": info["crossing"],
    },
}
json.dump(manifest, open(sys.argv[2], "w"), indent=2)
open(sys.argv[2], "a").write("\n")
