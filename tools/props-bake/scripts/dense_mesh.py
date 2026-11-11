"""The dense, coloured intermediate mesh for one prop: idol/scripts/splat2mesh.convert with a
higher budget than its CLI allows (that budget is for final assets; remesh_prop.py makes those).

Usage: python -I dense_mesh.py <in.ply> <out dir> <name>
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from splat2mesh import convert  # noqa: E402

src, out, name = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
print(json.dumps(convert(src, out, tris=40000, texture=1024, grid=200, height=1.0, name=name)))
