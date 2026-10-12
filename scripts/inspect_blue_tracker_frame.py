"""Inspect a raw 800x480 BGR DDR snapshot and render a PNG using the standard library."""
import argparse
import json
from pathlib import Path
import struct
import zlib

parser = argparse.ArgumentParser()
parser.add_argument("file", type=Path)
parser.add_argument("--mode", type=int, choices=(0, 1, 2), required=True)
args = parser.parse_args()
data = args.file.read_bytes()
assert len(data) == 800 * 480 * 3
black = white = green = blue = 0
xmin, xmax, ymin, ymax = 800, -1, 480, -1
for i in range(0, len(data), 3):
    b, g, r = data[i:i+3]
    black += (r, g, b) == (0, 0, 0)
    white += (r, g, b) == (255, 255, 255)
    blue += b >= 80 and b > r + 35 and b > g + 20
    if (r, g, b) == (0, 255, 0):
        green += 1
        x, y = (i // 3) % 800, (i // 3) // 800
        xmin, xmax, ymin, ymax = min(xmin, x), max(xmax, x), min(ymin, y), max(ymax, y)
result = dict(mode=args.mode, pixels=800*480, black=black, white=white,
              green=green, blue_threshold_pixels=blue,
              green_extent=[xmin, xmax, ymin, ymax] if green else None,
              non_atomic_snapshot=True)
if args.mode == 1:
    result["mask_only_black_white"] = black + white == 800*480
args.file.with_suffix(".json").write_text(json.dumps(result, indent=2))
print(json.dumps(result))
# Lossless RGB PNG, using only the standard library.
rgb = bytearray(len(data))
rgb[0::3], rgb[1::3], rgb[2::3] = data[2::3], data[1::3], data[0::3]
rows = b"".join(b"\0" + rgb[y*2400:(y+1)*2400] for y in range(480))
def chunk(kind, payload):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 800, 480, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
args.file.with_suffix(".png").write_bytes(png)
