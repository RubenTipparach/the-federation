#!/usr/bin/env python3
# Generates the committed subsystem icons in assets/icons/.
#
# Per CLAUDE.md section 3 an art asset is delivered as a .png, and per section 2
# a script may generate an asset only if it writes the file to disk. This writes
# one 48x48 RGBA .png per subsystem code. Run it, then commit the .png files.
#
# The glyphs are white with an alpha mask, so the ship systems display tints
# them with the family colour it already uses (Palette.family_color) instead of
# shipping one file per colour.
#
# Usage: python3 tools/gen_icons.py

import math
import os
import struct
import zlib

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "icons")
SIZE = 48
SS = 3  # supersampling factor, so edges are not stair steps


# ---- tiny rasteriser ---------------------------------------------------------
#
# Coverage only: every primitive paints white and accumulates into an alpha
# buffer. That is all an icon mask needs, and it keeps this file dependency
# free, which matters because the build machines have no image libraries.


class Canvas:
    def __init__(self):
        self.w = SIZE * SS
        self.a = [0.0] * (self.w * self.w)

    def _put(self, x, y, v=1.0):
        if 0 <= x < self.w and 0 <= y < self.w:
            i = y * self.w + x
            if v > self.a[i]:
                self.a[i] = v

    def poly(self, pts):
        """Filled polygon, even odd scanline fill. Points are in icon space."""
        p = [(x * SS, y * SS) for (x, y) in pts]
        ys = [y for (_, y) in p]
        for sy in range(max(0, int(min(ys))), min(self.w, int(max(ys)) + 1)):
            yc = sy + 0.5
            xs = []
            for i in range(len(p)):
                x0, y0 = p[i]
                x1, y1 = p[(i + 1) % len(p)]
                if (y0 <= yc < y1) or (y1 <= yc < y0):
                    t = (yc - y0) / (y1 - y0)
                    xs.append(x0 + t * (x1 - x0))
            xs.sort()
            for k in range(0, len(xs) - 1, 2):
                for sx in range(int(xs[k]), int(xs[k + 1]) + 1):
                    self._put(sx, sy)

    def disc(self, cx, cy, r, inner=0.0):
        """Filled circle, or a ring when inner is non zero."""
        cx, cy, r, inner = cx * SS, cy * SS, r * SS, inner * SS
        for sy in range(max(0, int(cy - r - 1)), min(self.w, int(cy + r + 2))):
            for sx in range(max(0, int(cx - r - 1)), min(self.w, int(cx + r + 2))):
                d = math.hypot(sx + 0.5 - cx, sy + 0.5 - cy)
                if inner <= d <= r:
                    self._put(sx, sy)

    def bar(self, x0, y0, x1, y1, thick):
        """Round capped line."""
        ax, ay, bx, by = x0 * SS, y0 * SS, x1 * SS, y1 * SS
        h = thick * SS * 0.5
        lo_x = int(min(ax, bx) - h - 1)
        hi_x = int(max(ax, bx) + h + 2)
        lo_y = int(min(ay, by) - h - 1)
        hi_y = int(max(ay, by) + h + 2)
        dx, dy = bx - ax, by - ay
        ln2 = dx * dx + dy * dy or 1.0
        for sy in range(max(0, lo_y), min(self.w, hi_y)):
            for sx in range(max(0, lo_x), min(self.w, hi_x)):
                px, py = sx + 0.5 - ax, sy + 0.5 - ay
                t = max(0.0, min(1.0, (px * dx + py * dy) / ln2))
                if math.hypot(px - t * dx, py - t * dy) <= h:
                    self._put(sx, sy)

    def arc(self, cx, cy, r, thick, deg_from, deg_to):
        """Arc band, angles measured clockwise from straight up."""
        steps = max(8, int(abs(deg_to - deg_from) / 4))
        prev = None
        for i in range(steps + 1):
            d = math.radians(deg_from + (deg_to - deg_from) * i / steps)
            p = (cx + math.sin(d) * r, cy - math.cos(d) * r)
            if prev is not None:
                self.bar(prev[0], prev[1], p[0], p[1], thick)
            prev = p

    def to_png(self, path):
        # Box downsample the supersampled coverage into the final alpha.
        rows = []
        for y in range(SIZE):
            row = bytearray([0])  # filter byte 0
            for x in range(SIZE):
                acc = 0.0
                for oy in range(SS):
                    for ox in range(SS):
                        acc += self.a[(y * SS + oy) * self.w + x * SS + ox]
                alpha = int(round(255 * acc / (SS * SS)))
                row += bytes((255, 255, 255, alpha))
            rows.append(bytes(row))
        raw = b"".join(rows)

        def chunk(tag, data):
            return (struct.pack(">I", len(data)) + tag + data
                    + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

        png = (b"\x89PNG\r\n\x1a\n"
               + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
               + chunk(b"IDAT", zlib.compress(raw, 9))
               + chunk(b"IEND", b""))
        with open(path, "wb") as f:
            f.write(png)


# ---- the glyphs --------------------------------------------------------------
#
# One function per subsystem code. Icon space is 48x48 with a 4 unit margin.
# Shapes are deliberately blunt: at 18 pixels in a fitting panel, detail is
# noise. What has to read instantly is which family a system belongs to and
# which system it is within that family.


def ph1(c):      # beam emitter: a dish firing forward
    c.arc(24, 30, 13, 4, -70, 70)
    c.bar(24, 26, 24, 8, 3.5)
    c.disc(24, 30, 4)


def ph3(c):      # light beam emitter: the same dish, smaller, twin barrels
    c.arc(24, 32, 10, 3.5, -70, 70)
    c.bar(20, 28, 20, 14, 3)
    c.bar(28, 28, 28, 14, 3)


def phot(c):     # torpedo tube: a warhead leaving a tube
    c.poly([(24, 6), (32, 20), (24, 26), (16, 20)])
    c.bar(14, 34, 34, 34, 4)
    c.bar(19, 40, 29, 40, 4)


def disr(c):     # disruptor: a bolt
    c.poly([(28, 5), (16, 25), (23, 25), (19, 43), (33, 21), (25, 21)])


def lnce(c):     # lance: a long spike with a heavy base
    c.poly([(24, 4), (30, 30), (18, 30)])
    c.bar(14, 36, 34, 36, 5)


def drn(c):      # drone rack: a finned missile
    c.poly([(24, 6), (29, 18), (29, 34), (19, 34), (19, 18)])
    c.poly([(19, 30), (12, 40), (19, 40)])
    c.poly([(29, 30), (36, 40), (29, 40)])


def brdg(c):     # bridge: a dome on a deck
    c.arc(24, 30, 12, 4, -90, 90)
    c.bar(10, 32, 38, 32, 4)
    c.disc(24, 22, 3)


def warp(c):     # warp core: an hourglass reactor
    c.poly([(14, 6), (34, 6), (27, 24), (34, 42), (14, 42), (21, 24)])


def imp(c):      # impulse deck: a nozzle with thrust behind it
    c.poly([(14, 6), (34, 6), (30, 24), (18, 24)])
    c.bar(17, 31, 31, 31, 4)
    c.bar(20, 40, 28, 40, 4)


def auxp(c):     # auxiliary power: a smaller reactor with a feed
    c.disc(24, 22, 11, 7)
    c.bar(24, 33, 24, 43, 4)


def btty(c):     # battery: a cell with a terminal
    c.poly([(12, 14), (36, 14), (36, 42), (12, 42)])
    c.bar(20, 10, 28, 10, 5)
    c.bar(18, 28, 30, 28, 4)


def shtl(c):     # shuttle bay: a craft leaving an opening
    c.bar(8, 40, 40, 40, 5)
    c.poly([(24, 8), (34, 30), (14, 30)])


def tran(c):     # transporter: a pad under a dematerialising column
    c.disc(24, 14, 9, 5)
    c.bar(16, 27, 32, 27, 3)
    c.bar(18, 34, 30, 34, 3)
    c.bar(12, 42, 36, 42, 4)


def trac(c):     # tractor beam: emitter with widening arcs
    c.disc(12, 24, 5)
    c.arc(12, 24, 13, 3.5, 30, 150)
    c.arc(12, 24, 21, 3.5, 40, 140)


def prb(c):      # probe: a body with an antenna
    c.disc(24, 30, 8, 4)
    c.bar(24, 22, 24, 6, 3)
    c.bar(17, 8, 31, 8, 3)


def lab(c):      # science lab: a flask
    c.poly([(19, 6), (29, 6), (29, 20), (38, 42), (10, 42), (19, 20)])


def mrne(c):     # marines: a boarding shield
    c.poly([(24, 5), (39, 12), (35, 34), (24, 43), (13, 34), (9, 12)])


def hull(c):     # hull: a plated section
    c.poly([(8, 12), (40, 12), (40, 36), (8, 36)])
    c.bar(8, 24, 40, 24, 3)
    c.bar(24, 12, 24, 36, 3)


def armr(c):     # armor: layered chevrons
    c.poly([(24, 6), (40, 18), (34, 18), (24, 12), (14, 18), (8, 18)])
    c.poly([(24, 20), (40, 32), (34, 32), (24, 26), (14, 32), (8, 32)])
    c.poly([(24, 34), (40, 46), (34, 46), (24, 40), (14, 46), (8, 46)])


# ---- station glyphs ----------------------------------------------------------
#
# The tactical view's subsystem tabs are labelled with the same masks, because
# a tab is the console for a box and should carry that box's mark. Six of the
# ten tabs already have one: reactor is WARP, tractor is TRAC, marines is MRNE,
# shuttle is SHTL, science is LAB. These are the four that answer to no single
# box, plus the shield tab, which answers to the ring rather than to a system.


# The rasteriser only ever ADDS coverage, so a line drawn inside a filled shape
# is invisible: white on white. Anything that needs internal detail is built as
# an outline out of bars, with the detail sitting in the empty middle.


def _outline(c, pts, w):
    """Closed outline through pts, since there is no stroke primitive."""
    for i in range(len(pts)):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % len(pts)]
        c.bar(x0, y0, x1, y1, w)


def shld(c):     # shields: the six facing ring, flat side to the bow
    hexa = []
    for i in range(6):
        a = math.radians(30 + i * 60)
        hexa.append((24 + 19 * math.sin(a), 24 - 19 * math.cos(a)))
    _outline(c, hexa, 4)
    c.disc(24, 24, 5)


def sens(c):     # sensors: a dish sweeping, with returns
    c.arc(24, 40, 18, 4, -80, 80)
    c.bar(24, 36, 24, 20, 3)
    c.arc(24, 40, 26, 3, -34, -10)
    c.arc(24, 40, 26, 3, 10, 34)


def rpr(c):      # repairs: a spanner, open jaw at the top
    c.disc(15, 14, 10, 5)
    c.bar(19, 20, 39, 40, 7)
    c.poly([(8, 8), (20, 8), (14, 16)])


def life(c):     # life support: a pulse trace
    c.bar(4, 24, 16, 24, 4)
    c.bar(16, 24, 21, 10, 4)
    c.bar(21, 10, 27, 38, 4)
    c.bar(27, 38, 32, 24, 4)
    c.bar(32, 24, 44, 24, 4)


def cargo(c):    # cargo: a crate, banded
    _outline(c, [(8, 13), (40, 13), (40, 41), (8, 41)], 4)
    c.bar(8, 22, 40, 22, 3)
    c.bar(19, 24, 19, 39, 3)
    c.bar(29, 24, 29, 39, 3)


def trsh(c):     # discard: a bin with its lid lifted clear of the body
    c.bar(8, 13, 40, 13, 4)
    c.bar(20, 7, 28, 7, 4)
    _outline(c, [(13, 19), (35, 19), (32, 44), (16, 44)], 4)
    c.bar(21, 24, 20, 40, 3)
    c.bar(27, 24, 28, 40, 3)


# The only glyph here that is not a ship system. Settings is chrome rather
# than hardware, but it is drawn by the same generator and shipped as the same
# white mask, because a second way of making an icon is a second thing to keep
# in step (CLAUDE.md 4.1).


def gear(c):     # settings: an eight tooth gear with an open hub
    # Eight, because six reads as a flower and twelve turns to mush at the 18
    # pixels the top bar draws it at.
    c.disc(24, 24, 14, 7)
    for i in range(8):
        a = math.radians(i * 45)
        # 19 rather than 21: a bar is drawn with its thickness centred on the
        # end point, so a tooth reaching 21 puts its tip at 24.5 from centre
        # and the four axis aligned ones get flattened against the edge of a
        # 48 pixel canvas.
        c.bar(24 + 12 * math.sin(a), 24 - 12 * math.cos(a),
              24 + 19 * math.sin(a), 24 - 19 * math.cos(a), 7)


ICONS = {
    "PH-1": ph1, "PH-3": ph3, "PHOT": phot, "DISR": disr, "LNCE": lnce,
    "DRN": drn, "BRDG": brdg, "WARP": warp, "IMP": imp, "AUXP": auxp,
    "BTTY": btty, "SHTL": shtl, "TRAN": tran, "TRAC": trac, "PRB": prb,
    "LAB": lab, "MRNE": mrne, "HULL": hull, "ARMR": armr,
    "SHLD": shld, "SENS": sens, "RPR": rpr, "LIFE": life, "CARGO": cargo,
    "TRSH": trsh,
    "GEAR": gear,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for code, draw in sorted(ICONS.items()):
        canvas = Canvas()
        draw(canvas)
        name = code.lower().replace("-", "") + ".png"
        canvas.to_png(os.path.join(OUT, name))
        print("wrote %s" % name)


if __name__ == "__main__":
    main()
