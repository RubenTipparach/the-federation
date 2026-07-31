#!/usr/bin/env python3
# Bakes the sky shader's lookup ramps from data/palette.json into a committed
# PNG (CLAUDE.md sections 3 and 3.1).
#
# The sky shader cannot read the palette file, and a shader that blended its
# own colors would put thousands of off palette pixels on screen. So it does
# not blend: it indexes this texture, sampled with nearest filtering, which
# means every pixel of sky is literally a palette entry and a palette swap is
# still a one file change.
#
# The image is one row per ramp, in the order the shader's ROW_ constants
# expect, so adding a ramp means adding it to both this file's ORDER and the
# shader. Row order is asserted rather than inferred from dictionary order.
#
# Usage: python3 tools/gen_ramps.py

import os

from shiplib import Px, load_ramps

HERE = os.path.dirname(os.path.abspath(__file__))
TEX_OUT = os.path.join(HERE, "..", "assets", "textures")
PALETTE = os.path.join(HERE, "..", "data", "palette.json")

# Row order, matched by the ROW_ constants in assets/shaders/sky_stars.gdshader.
ORDER = ("nebula_cool", "nebula_warm", "star_dim", "star")


def main():
    os.makedirs(TEX_OUT, exist_ok=True)
    ramps = load_ramps(PALETTE)
    missing = set(ORDER) - set(ramps)
    assert not missing, "ramps missing from the palette file: %r" % (missing,)
    extra = set(ramps) - set(ORDER)
    assert not extra, "ramps the shader has no row for: %r" % (extra,)

    width = len(ramps[ORDER[0]])
    # The canvas is square because Px is square; the rows past the last ramp
    # stay black and are never sampled, since the shader indexes rows by a
    # constant over the ramp count.
    p = Px(width)
    for row, name in enumerate(ORDER):
        for x, rgb in enumerate(ramps[name]):
            p.put(x, row, rgb)
    p.save(os.path.join(TEX_OUT, "sky_ramps.png"))
    print("baked %d ramps of %d steps" % (len(ORDER), width))


if __name__ == "__main__":
    main()
