"""Packs a splat PLY (nooki-scene/generate/make_splat.py's layout: 14 floats per splat, SH degree 0)
into an .spz file, version 2 of Niantic's format, which SplatLoader reads.

  python3 Tools/ply_to_spz.py Mochi.ply Nooki/Resources/Mochi.spz

The splats keep their order, so a .skin written against the PLY still fits.
"""

import gzip
import struct
import sys

import numpy as np

FIELDS = "x y z scale_0 scale_1 scale_2 rot_0 rot_1 rot_2 rot_3 opacity f_dc_0 f_dc_1 f_dc_2".split()
MAGIC = 0x5053474E
VERSION = 2
FRACTIONAL_BITS = 12
COLOR_SCALE = 0.15


def read_ply(path):
    data = open(path, "rb").read()
    end = data.index(b"end_header\n") + len(b"end_header\n")
    header = data[:end].decode().splitlines()
    assert "format binary_little_endian 1.0" in header, "not a little-endian binary PLY"
    props = [line.split()[2] for line in header if line.startswith("property float ")]
    assert props == FIELDS, f"unexpected properties {props}"
    count = int(next(line for line in header if line.startswith("element vertex ")).split()[2])
    body = np.frombuffer(data[end:], dtype="<f4")
    assert body.size == count * len(FIELDS), "body size does not match the vertex count"
    return body.reshape(count, len(FIELDS))


def to_u8(values):
    return np.clip(np.round(values), 0, 255).astype(np.uint8)


def pack(splats):
    count = len(splats)
    position = np.round(splats[:, 0:3] * (1 << FRACTIONAL_BITS)).astype(np.int64)
    limit = 1 << 23
    assert np.all((position >= -limit) & (position < limit)), "a position does not fit 24 bits"
    position = (position & 0xFFFFFF).astype(np.uint32)
    position_bytes = np.stack([position & 0xFF, (position >> 8) & 0xFF, position >> 16], axis=-1)

    alpha = to_u8(255 / (1 + np.exp(-splats[:, 10])))
    color = to_u8(splats[:, 11:14] * (COLOR_SCALE * 255) + 0.5 * 255)
    scale = to_u8((splats[:, 3:6] + 10) * 16)

    # The PLY stores w first; spz keeps x, y, z of the unit quaternion with w >= 0.
    q = splats[:, 6:10] / np.linalg.norm(splats[:, 6:10], axis=1, keepdims=True)
    q = np.where(q[:, :1] < 0, -q, q)
    rotation = to_u8(q[:, 1:4] * 127.5 + 127.5)

    header = struct.pack("<IIIBBBB", MAGIC, VERSION, count, 0, FRACTIONAL_BITS, 0, 0)
    parts = [position_bytes.astype(np.uint8), alpha, color, scale, rotation]
    return gzip.compress(header + b"".join(p.tobytes() for p in parts), compresslevel=9, mtime=0)


def main():
    source, target = sys.argv[1:3]
    splats = read_ply(source)
    packed = pack(splats)
    open(target, "wb").write(packed)
    print(f"{target}: {len(splats)} splats, {len(packed) / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
