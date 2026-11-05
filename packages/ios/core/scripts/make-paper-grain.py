"""Makes the note widget's paper grain: a 96 px tile that repeats without a seam.

Fine grain plus a few long soft fibres, as an alpha mask of a warm grey, so it
only ever darkens the paper a little and the ink stays crisp. Seeded, so it is the same every run.

    python3 packages/ios/core/scripts/make-paper-grain.py
"""

from pathlib import Path

import numpy as np
from PIL import Image

SIZE = 96
OUT = Path(__file__).resolve().parent.parent / "Sources/DesignSystem/Resources/Paper/paper-grain.png"


def blur_wrapped(field: np.ndarray, radius: int) -> np.ndarray:
    """A box blur that wraps at the edges, so the tile stays seamless."""
    out = field.copy()
    for axis in (0, 1):
        acc = np.zeros_like(out)
        for shift in range(-radius, radius + 1):
            acc += np.roll(out, shift, axis=axis)
        out = acc / (2 * radius + 1)
    return out


def main() -> None:
    rng = np.random.default_rng(20261102)
    fine = rng.random((SIZE, SIZE))
    soft = blur_wrapped(rng.random((SIZE, SIZE)), 3)
    soft = (soft - soft.min()) / (soft.max() - soft.min())
    # Fibres: short wavy strokes in all directions, wrapped round the tile.
    fibres = np.zeros((SIZE, SIZE))
    for _ in range(28):
        x, y = rng.random(2) * SIZE
        angle = rng.random() * np.pi
        length = 4 + rng.random() * 10
        for t in np.linspace(0, length, int(length * 2)):
            bend = np.sin(t / 4 + x) * 0.6
            px = int(x + np.cos(angle) * t - np.sin(angle) * bend) % SIZE
            py = int(y + np.sin(angle) * t + np.cos(angle) * bend) % SIZE
            fibres[py, px] = 1
    fibres = blur_wrapped(fibres, 1)
    alpha = 0.5 * fine + 0.5 * soft + 0.35 * fibres
    alpha = np.clip(alpha / alpha.max(), 0, 1)
    # At most about 8 % of the shadow colour over the paper, in a few steps so the file stays small.
    alpha8 = (np.round(alpha * 5) * 4).astype(np.uint8)
    # One flat warm grey with the grain in its alpha: the paper's own colour shows through.
    la = np.zeros((SIZE, SIZE, 2), dtype=np.uint8)
    la[..., 0] = 0x4E
    la[..., 1] = alpha8
    OUT.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(la, "LA").save(OUT, optimize=True)
    print(OUT, OUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
