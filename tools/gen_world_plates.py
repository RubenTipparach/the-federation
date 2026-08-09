#!/usr/bin/env python3
# Composes the world concept plates in docs/images/worlds/ from the renders
# tools/shoot_worlds.gd writes beside them.
#
# Run scripts/gen-world-plates.sh rather than this directly: the renders have to
# come out of a running Godot, because a world is a shader tracing a sphere and
# there is no second implementation of it here to draw from (CLAUDE.md 4.1).
# This step only arranges what that produced.
#
# There is deliberately no resampling in here. The renders arrive at the size
# the plates use, so a plate is the render, pixel for pixel.
#
# NOTE what this file no longer does. It used to assert that every rendered
# pixel was a palette entry, because the worlds were drawn by shaders that never
# blended. The planet shader ramps between colours, so that gate would now fail
# on every world by design. The palette still decides the four colours a world
# is built from; it no longer decides every pixel. That is the documented
# exception in CLAUDE.md section 7, and this comment is here so nobody restores
# the check and concludes the art is broken.
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
SLOTS = ["low", "mid", "high", "rim"]

PAD = 24
GAP = 24
SWATCH = 40


def rgb(hex_text):
    t = hex_text.lstrip("#")
    return tuple(int(t[i:i + 2], 16) for i in (0, 2, 4))


def load_palette():
    """The palette as one pool, the way src/ui/palette.gd named() resolves it.

    A world slot may name a colour from either pool: the ice world's limb is
    `shield_hi`, which lives in ui_colors."""
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


def swatches(roles, colors, width, height):
    """The four colours this world is built from."""
    strip = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    step = width // len(roles)
    for i, role in enumerate(roles):
        block = Image.new("RGBA", (step, height), colors[role] + (255,))
        strip.paste(block, (i * step, 0))
    return strip


def plate(variant, roles, colors, ground):
    """One variant's plate: three real draws of that world, and its colours."""
    shots = [native(variant, s) for s in range(SEEDS)]
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


def lineup(ground):
    """One of each, so the four can be told apart at a glance."""
    shots = [native(v, 0) for v in VARIANTS]
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
        roles = [worlds[variant][slot] for slot in SLOTS]
        out = os.path.join(OUT, "%s.png" % variant)
        plate(variant, roles, colors, ground).save(out)
        print("wrote docs/images/worlds/%s.png  (%s)"
              % (variant, ", ".join(roles)))

    lineup(ground).save(os.path.join(OUT, "lineup.png"))
    print("wrote docs/images/worlds/lineup.png")


if __name__ == "__main__":
    main()
