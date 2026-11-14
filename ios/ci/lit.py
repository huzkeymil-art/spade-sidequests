#!/usr/bin/env python3
"""Prints how much of the upper part of a screenshot is drawn on, as a percentage.

The 3D scene fills the upper part of most screens. If that area is still the
plain background colour, the scene never drew. Needs only Python itself.

    python3 lit.py screenshot.png
"""
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

INK = (13, 15, 12)  # the app's background colour


def read_png(path):
    """Returns (width, height, rows), where each row is a list of (r, g, b)."""
    data = open(path, "rb").read()
    at, packed = 8, b""
    width = height = depth = kind = 0
    while at < len(data):
        length, = struct.unpack_from(">I", data, at)
        name = data[at + 4:at + 8]
        body = data[at + 8:at + 8 + length]
        if name == b"IHDR":
            width, height, depth, kind = struct.unpack_from(">IIBB", body)
        elif name == b"IDAT":
            packed += body
        at += 12 + length
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[kind]
    size = channels * depth // 8          # bytes per pixel
    stride = width * size
    raw = zlib.decompress(packed)
    rows, previous = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        method = raw[start]
        line = bytearray(raw[start + 1:start + 1 + stride])
        # Each row is stored as differences from its neighbours; undo that.
        for i in range(stride):
            left = line[i - size] if i >= size else 0
            up = previous[i]
            corner = previous[i - size] if i >= size else 0
            if method == 1:
                guess = left
            elif method == 2:
                guess = up
            elif method == 3:
                guess = (left + up) // 2
            elif method == 4:
                p = left + up - corner
                dl, du, dc = abs(p - left), abs(p - up), abs(p - corner)
                guess = left if dl <= du and dl <= dc else up if du <= dc else corner
            else:
                guess = 0
            line[i] = (line[i] + guess) & 255
        step = depth // 8                 # with 16-bit colour, the first byte of each value is enough
        pixels = []
        for x in range(width):
            base = x * size
            if channels >= 3:
                pixels.append((line[base], line[base + step], line[base + 2 * step]))
            else:
                pixels.append((line[base],) * 3)
        rows.append(pixels)
        previous = line
    return width, height, rows


def main():
    source = sys.argv[1]
    small = source
    if shutil.which("sips"):
        # Shrink it first: a small picture is all this needs, and it reads much faster.
        small = os.path.join(tempfile.mkdtemp(), "small.png")
        subprocess.run(["sips", "-Z", "240", source, "--out", small], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    width, height, rows = read_png(small)
    drawn = total = 0
    # From just under the status bar down to where the lowest panel can begin.
    for y in range(int(height * 0.10), int(height * 0.34)):
        for r, g, b in rows[y]:
            total += 1
            if max(abs(r - INK[0]), abs(g - INK[1]), abs(b - INK[2])) > 6:
                drawn += 1
    print(round(100 * drawn / max(total, 1)))


main()
