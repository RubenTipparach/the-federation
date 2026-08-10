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

VARIANTS = ["terran", "jungle", "volcanic", "ice", "barren", "gas", "moon"]
SEEDS = 3
SLOTS = ["abyss", "sea", "shore", "land", "peak", "cap", "rim", "glow"]

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


# One line about what each world IS. This is prose about the art rather than a
# setting, so it lives here beside the generator that prints it rather than in
# data/, and there is still only one copy of it.
BLURBS = {
    "terran": "Somebody lives here. The only world that implies a reason for "
              "the battle: ocean, continents, ice at both poles.",
    "jungle": "Terran, further along. Canopy edge to edge with the water caught "
              "inland, and no ice at all, which is how you tell them apart.",
    "volcanic": "Still cooling. Dark rock cut by fissures that have not closed, "
                "and the only world that keeps its own light at night.",
    "ice": "Terran once, or never quite. The sheet reaches the tropics and the "
           "sea shows through where it has not closed over.",
    "barren": "Nothing happened here and nothing will. Airless, so its limb is "
              "a hard edge with no haze on it.",
    "gas": "Not a place to land. Belts all the way down, and the only world "
           "with a ring.",
    "moon": "Something a world caught. Solid, and it collides like one, but it "
            "has no well of its own.",
}


def index(data):
    """planets.md: every world, its picture and what it is, on one page.

    Generated rather than written, so it cannot come to disagree with the game
    the way a hand kept table would."""
    worlds = data["worlds"]
    shapes = data["_tuning"]["terrain_view"]["planets"]
    out = []
    out.append("# Planets")
    out.append("")
    out.append("Every kind of world an arena can hold. **This file is "
               "generated**: run `./scripts/gen-world-plates.sh`, which renders "
               "each world through the same scene a battle uses and rewrites "
               "the table below. Do not hand edit it.")
    out.append("")
    out.append("The concept behind each one, and what a world does to a ship, "
               "is [docs/15-worlds.md](docs/15-worlds.md). How they are drawn, "
               "and why this game is GPL-3.0, is "
               "[docs/14-reference-planet-shader.md](docs/14-reference-planet-shader.md).")
    out.append("")
    out.append("![Every world](docs/images/worlds/lineup.png)")
    out.append("")
    out.append("| | World | What it is |")
    out.append("|---|---|---|")
    for v in VARIANTS:
        shot = "docs/images/worlds/native/%s-0.png" % v
        out.append('| <img src="%s" width="150"> | **%s** | %s |'
                   % (shot, v, BLURBS[v]))
    out.append("")
    out.append("## What each one has")
    out.append("")
    out.append("| World | Air | Cloud | Ice | Night glow | Ring | Belts |")
    out.append("|---|---|---|---|---|---|---|")
    for v in VARIANTS:
        s = shapes[v]
        w = worlds[v]
        # A level above what the terrain can reach never appears, which is how a
        # world has no ice; 0.2 is comfortably past the tallest ground.
        row = [
            v,
            "yes" if float(s["atmosphere_density"]) > 0.0 else "none",
            "yes" if float(s["clouds_density"]) > 0.0 else "none",
            "yes" if float(s["ice_level"]) < 0.2 and w["cap"] else "none",
            "yes" if w["glow"] else "none",
            "yes" if v == "gas" else "none",
            "yes" if float(s["bands"]) > 0.0 else "none",
        ]
        out.append("| " + " | ".join(row) + " |")
    out.append("")
    out.append("## What each one is made of")
    out.append("")
    out.append("Palette roles from `data/palette.json`, lowest ground first. "
               "An empty cell means the world has none of that thing.")
    out.append("")
    out.append("| World | " + " | ".join("`%s`" % s for s in SLOTS) + " |")
    out.append("|---|" + "---|" * len(SLOTS))
    for v in VARIANTS:
        cells = [("`%s`" % worlds[v][slot]) if worlds[v][slot] else ""
                 for slot in SLOTS]
        out.append("| " + v + " | " + " | ".join(cells) + " |")
    out.append("")
    return "\n".join(out)


def main():
    data, colors = load_palette()
    worlds = data["worlds"]
    # The void the tactical view draws worlds against, so a plate shows the
    # contrast the player actually gets rather than a flattering grey.
    ground = colors["black"]
    os.makedirs(OUT, exist_ok=True)

    for variant in VARIANTS:
        # A world with no polar cap and no glowing ground names neither, and an
        # empty name has no swatch to draw.
        roles = [worlds[variant][slot] for slot in SLOTS
                 if worlds[variant][slot]]
        out = os.path.join(OUT, "%s.png" % variant)
        plate(variant, roles, colors, ground).save(out)
        print("wrote docs/images/worlds/%s.png  (%s)"
              % (variant, ", ".join(roles)))

    lineup(ground).save(os.path.join(OUT, "lineup.png"))
    print("wrote docs/images/worlds/lineup.png")

    with open(os.path.join(HERE, "..", "data", "tuning.json")) as f:
        data["_tuning"] = json.load(f)
    with open(os.path.join(HERE, "..", "planets.md"), "w") as f:
        f.write(index(data))
    print("wrote planets.md")


if __name__ == "__main__":
    main()
