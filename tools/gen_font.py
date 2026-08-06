#!/usr/bin/env python3
# Generates the committed tactical bitmap face in assets/ui/.
#
# Writes two files, both committed (CLAUDE.md 3, and 5.1's rule that a script
# may generate an asset only by writing it to disk):
#
#   font_tactical.png   the glyph atlas
#   font_tactical.fnt   BMFont metrics, which Godot imports as a FontFile
#
# The face is 5x7 capitals, baked at 1x so a glyph is 5x7 device pixels and a
# line is 9. Baked rather than scaled: Godot would filter a fractionally scaled
# bitmap face and filtering is the one thing that stops pixel type reading as
# pixel type.
#
# BAKED SMALL ON PURPOSE. Godot scales a bitmap face by whole numbers only
# (see the import note below), so the size it is baked at is the SMALLEST it
# can ever draw, and every other size is a multiple of it. Baked at 7 the face
# serves 7, 14 and 21 from one atlas; baked at 14 it could only ever serve 14
# and 28, which is why the interface could not be made smaller until this
# changed.
#
# THE IMPORT MUST STAY ON INTEGER SCALING. assets/ui/font_tactical.fnt.import
# carries scaling_mode=1, which is Godot's FIXED_SIZE_SCALE_INTEGER_ONLY. It
# shipped as 2 (fractional) for a while and every label in the game was being
# resampled at 0.79x, 0.86x, 0.93x or 1.21x with a filter over it, which is
# exactly the soft grey fringing pixel type must never have.
#
# Ask for 7, 14 or 21 and nothing else. A request between them is rounded to
# the nearest multiple, so it is not a size, it is a lie about a size.
#
# Lowercase maps to the same rects as uppercase. The face has no lowercase by
# design, and pointing the codepoints at the capitals means existing UI strings
# render as small caps instead of rendering as nothing.
#
# The atlas is white with an alpha mask so Godot tints it per control, the same
# trick the subsystem icons use: one file serves every colour the skin has.
#
# Usage: python3 tools/gen_font.py

import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(__file__))

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui")

# One art pixel is this many device pixels. Must match tools/gen_ui_plates.py.
B = 1
GW, GH = 5, 7          # glyph box, in art pixels
ADVANCE = 6            # pen movement, in art pixels: one column of air
LINE = 9               # line height, in art pixels
COLS = 16              # glyphs per atlas row

GLYPHS = {
    "A": "01110 10001 10001 11111 10001 10001 10001",
    "B": "11110 10001 10001 11110 10001 10001 11110",
    "C": "01110 10001 10000 10000 10000 10001 01110",
    "D": "11100 10010 10001 10001 10001 10010 11100",
    "E": "11111 10000 10000 11110 10000 10000 11111",
    "F": "11111 10000 10000 11110 10000 10000 10000",
    "G": "01110 10001 10000 10111 10001 10001 01111",
    "H": "10001 10001 10001 11111 10001 10001 10001",
    "I": "11111 00100 00100 00100 00100 00100 11111",
    "J": "00111 00010 00010 00010 00010 10010 01100",
    "K": "10001 10010 10100 11000 10100 10010 10001",
    "L": "10000 10000 10000 10000 10000 10000 11111",
    "M": "10001 11011 10101 10101 10001 10001 10001",
    "N": "10001 11001 11001 10101 10011 10011 10001",
    "O": "01110 10001 10001 10001 10001 10001 01110",
    "P": "11110 10001 10001 11110 10000 10000 10000",
    "Q": "01110 10001 10001 10001 10101 10010 01101",
    "R": "11110 10001 10001 11110 10100 10010 10001",
    "S": "01111 10000 10000 01110 00001 00001 11110",
    "T": "11111 00100 00100 00100 00100 00100 00100",
    "U": "10001 10001 10001 10001 10001 10001 01110",
    "V": "10001 10001 10001 10001 01010 01010 00100",
    "W": "10001 10001 10001 10101 10101 11011 10001",
    "X": "10001 01010 00100 00100 00100 01010 10001",
    "Y": "10001 10001 01010 00100 00100 00100 00100",
    "Z": "11111 00001 00010 00100 01000 10000 11111",
    "0": "01110 10001 10011 10101 11001 10001 01110",
    "1": "00100 01100 00100 00100 00100 00100 01110",
    "2": "01110 10001 00001 00010 00100 01000 11111",
    "3": "11110 00001 00001 01110 00001 00001 11110",
    "4": "00010 00110 01010 10010 11111 00010 00010",
    "5": "11111 10000 11110 00001 00001 10001 01110",
    "6": "00110 01000 10000 11110 10001 10001 01110",
    "7": "11111 00001 00010 00100 01000 01000 01000",
    "8": "01110 10001 10001 01110 10001 10001 01110",
    "9": "01110 10001 10001 01111 00001 00010 01100",
    " ": "00000 00000 00000 00000 00000 00000 00000",
    "#": "01010 11111 01010 01010 01010 11111 01010",
    "%": "11000 11001 00010 00100 01000 10011 00011",
    "'": "00100 00100 00000 00000 00000 00000 00000",
    "\"": "01010 01010 00000 00000 00000 00000 00000",
    "(": "00010 00100 01000 01000 01000 00100 00010",
    ")": "01000 00100 00010 00010 00010 00100 01000",
    "[": "01110 01000 01000 01000 01000 01000 01110",
    "]": "01110 00010 00010 00010 00010 00010 01110",
    ",": "00000 00000 00000 00000 00100 00100 01000",
    "-": "00000 00000 00000 01110 00000 00000 00000",
    ".": "00000 00000 00000 00000 00000 00100 00100",
    # The ellipsis, keyed by escape so this file stays plain ASCII. Without it
    # every text_overrun_behavior TRIM_ELLIPSIS in the project falls back to a
    # hard cut, which is the silent truncation CLAUDE.md 6.4 says not to ship.
    "\u2026": "00000 00000 00000 00000 00000 10101 10101",
    "/": "00001 00001 00010 00100 01000 10000 10000",
    "\\": "10000 10000 01000 00100 00010 00001 00001",
    ":": "00000 00100 00000 00000 00000 00100 00000",
    ";": "00000 00100 00000 00000 00100 00100 01000",
    "<": "00010 00100 01000 10000 01000 00100 00010",
    ">": "01000 00100 00010 00001 00010 00100 01000",
    "_": "00000 00000 00000 00000 00000 00000 11111",
    "+": "00000 00100 00100 11111 00100 00100 00000",
    "=": "00000 00000 11111 00000 11111 00000 00000",
    "!": "00100 00100 00100 00100 00100 00000 00100",
    "?": "01110 10001 00001 00010 00100 00000 00100",
    "*": "00000 10101 01110 11111 01110 10101 00000",
    "&": "01100 10010 10100 01000 10101 10010 01101",
}


def png_rgba(path, w, h, px):
    """px is a flat list of (r, g, b, a). No dependencies: the build machines
    have no image libraries, which is why every generator here writes its own."""
    rows = b"".join(b"\x00" + bytes(v for p in px[y * w:(y + 1) * w] for v in p)
                    for y in range(h))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n"
                + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(rows, 9))
                + chunk(b"IEND", b""))


def main():
    os.makedirs(OUT, exist_ok=True)
    order = sorted(GLYPHS)
    cw, ch = GW * B, GH * B
    rows = (len(order) + COLS - 1) // COLS
    w, h = COLS * cw, rows * ch
    px = [(255, 255, 255, 0)] * (w * h)

    placed = {}
    for n, ch_ in enumerate(order):
        cx, cy = (n % COLS) * cw, (n // COLS) * ch
        placed[ch_] = (cx, cy)
        bits = GLYPHS[ch_].split(" ")
        for j in range(GH):
            for i in range(GW):
                if bits[j][i] != "1":
                    continue
                for dy in range(B):
                    for dx in range(B):
                        px[(cy + j * B + dy) * w + cx + i * B + dx] = (255, 255, 255, 255)

    png_rgba(os.path.join(OUT, "font_tactical.png"), w, h, px)
    print("wrote font_tactical.png  (%dx%d, %d glyphs)" % (w, h, len(order)))

    # BMFont, the format Godot imports straight into a FontFile. Lowercase
    # points at the same rect as its capital: the face has no lowercase, and
    # small caps beats a row of missing glyph boxes.
    lines = [
        'info face="tactical" size=%d bold=0 italic=0 charset="" unicode=1 '
        'stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=0,0' % (GH * B),
        'common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0'
        % (LINE * B, GH * B, w, h),
        'page id=0 file="font_tactical.png"',
    ]
    entries = []
    for ch_, (cx, cy) in placed.items():
        codes = [ord(ch_)]
        if "A" <= ch_ <= "Z":
            codes.append(ord(ch_.lower()))
        for code in codes:
            entries.append(
                'char id=%d x=%d y=%d width=%d height=%d xoffset=0 yoffset=0 '
                'xadvance=%d page=0 chnl=15' % (code, cx, cy, cw, ch, ADVANCE * B))
    lines.append("chars count=%d" % len(entries))
    lines.extend(sorted(entries, key=lambda s: int(s.split()[1][3:])))
    with open(os.path.join(OUT, "font_tactical.fnt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote font_tactical.fnt  (%d codepoints)" % len(entries))


if __name__ == "__main__":
    main()
