#!/usr/bin/env python3
# Composes the world concept plates in docs/images/worlds/ from the native
# renders tools/shoot_worlds.gd writes beside them.
#
# Run scripts/gen-world-plates.sh rather than this directly: the renders have to
# come out of a running Godot, because the art is a vendored shader's output and
# there is no second implementation of it here to draw from (CLAUDE.md 4.1).
# This step only magnifies and arranges what that produced.
#
# Magnification is a whole number and nearest neighbour, always. These are pixel
# art at 100 pixels across; any other filter invents colours between the ones
# the shader emitted, and an invented colour is off palette by definition.
#
# The gas giant is drawn by its vendored scene into a viewport three times as
# wide as its body, because its ring is three times as wide as its body. The
# plates keep that: every world here is magnified by the same factor, so the
# lineup shows true relative extent rather than four bodies filed to one size.
#
# Usage: python3 tools/gen_world_plates.py

import json
import os

from PIL import Image

HERE = os.path.dirname(__file__)
PALETTE = os.path.join(HERE, "..", "data", "palette.json")
OUT = os.path.join(HERE, "..", "docs", "images", "worlds")
NATIVE = os.path.join(OUT, "native")

VARIANTS = ["terran", "ice", "barren", "gas"]
SEEDS = 3

# Whole number magnification, nearest neighbour. 3 puts a 100 pixel world at
# 300, which reads at a document's width without a single invented colour.
ZOOM = 3
PAD = 24
GAP = 24
SWATCH = 40


def rgb(hex_text):
    t = hex_text.lstrip("#")
    return tuple(int(t[i:i + 2], 16) for i in (0, 2, 4))


def load_palette():
    """The palette as one pool, the way src/ui/palette.gd named() resolves it.

    A world role may name a colour from either pool: the ice sheet's lit face is
    `shield_hi`, which lives in ui_colors. Checking against `colors` alone would
    call that off palette, which is the opposite of true."""
    with open(PALETTE) as f:
        data = json.load(f)
    pool = dict(data["colors"])
    pool.update(data["ui_colors"])
    return data, {name: rgb(v) for name, v in pool.items()}


def native(variant, seed):
    path = os.path.join(NATIVE, "%s-%d.png" % (variant, seed))
    assert os.path.exists(path), (
        "missing %s. Run scripts/gen-world-plates.sh, which renders these "
        "before composing." % path)
    return Image.open(path).convert("RGBA")


def check(image, allowed, where):
    """Every opaque pixel is a palette entry, or nothing is written.

    This is the same gate tools/shiplib.py verify() puts on the ships, applied
    to the worlds (CLAUDE.md 3.1). It is worth doing here even though the
    colours were handed to the shader from the palette, because it is the only
    thing that proves the shader did not blend two of them into a third."""
    seen = {px[:3] for px in image.getdata() if px[3] > 8}
    bad = seen - allowed
    assert not bad, "off palette pixels in %s: %r" % (where, sorted(bad))


def swatches(roles, colors, width, height):
    """The variant's ordered role list as a strip of blocks."""
    strip = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    if not roles:
        return strip
    step = width // len(roles)
    for i, role in enumerate(roles):
        block = Image.new("RGBA", (step, height), colors[role] + (255,))
        strip.paste(block, (i * step, 0))
    return strip


def plate(variant, roles, colors, ground):
    """One variant's plate: three real draws of that world, and its colours."""
    shots = []
    for s in range(SEEDS):
        img = native(variant, s)
        check(img, set(colors.values()), "%s-%d" % (variant, s))
        shots.append(img.resize(
            (img.width * ZOOM, img.height * ZOOM), Image.NEAREST))

    cell_w = max(i.width for i in shots)
    cell_h = max(i.height for i in shots)
    width = PAD * 2 + cell_w * SEEDS + GAP * (SEEDS - 1)
    height = PAD * 2 + cell_h + GAP + SWATCH
    canvas = Image.new("RGBA", (width, height), ground + (255,))
    for i, shot in enumerate(shots):
        x = PAD + i * (cell_w + GAP) + (cell_w - shot.width) // 2
        canvas.alpha_composite(shot, (x, PAD + (cell_h - shot.height) // 2))
    canvas.alpha_composite(
        swatches(roles, colors, width - PAD * 2, SWATCH),
        (PAD, PAD + cell_h + GAP))
    return canvas


def lineup(data, colors, ground):
    """One of each, at a single magnification, so the sizes are comparable."""
    shots = []
    for variant in VARIANTS:
        img = native(variant, 0)
        shots.append(img.resize(
            (img.width * ZOOM, img.height * ZOOM), Image.NEAREST))
    cell_h = max(i.height for i in shots)
    width = PAD * 2 + sum(i.width for i in shots) + GAP * (len(shots) - 1)
    canvas = Image.new("RGBA", (width, PAD * 2 + cell_h), ground + (255,))
    x = PAD
    for shot in shots:
        canvas.alpha_composite(shot, (x, PAD + (cell_h - shot.height) // 2))
        x += shot.width + GAP
    return canvas


def main():
    data, colors = load_palette()
    worlds = data["worlds"]
    # The void the tactical view draws worlds against, so a plate shows the
    # contrast the player actually gets rather than a flattering grey.
    ground = colors["black"]
    os.makedirs(OUT, exist_ok=True)

    for variant in VARIANTS:
        roles = [r for r in worlds[variant]]
        out = os.path.join(OUT, "%s.png" % variant)
        plate(variant, roles, colors, ground).save(out)
        print("wrote docs/images/worlds/%s.png  (%d colours)"
              % (variant, len(set(roles))))

    out = os.path.join(OUT, "lineup.png")
    lineup(data, colors, ground).save(out)
    print("wrote docs/images/worlds/lineup.png")


if __name__ == "__main__":
    main()
