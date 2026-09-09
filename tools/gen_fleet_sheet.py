#!/usr/bin/env python3
"""Build the fleet roster page: every hull, and the graphic set it ships.

WHY THIS EXISTS AND WHAT IT IS NOT.

`docs/mockups/starship-dioramas.html` is the kit review: it builds ships in
JavaScript so a shape can be argued about before it is committed. This is the
other end of the pipeline. Nothing here is drawn. Every image is a committed
PNG out of `assets/graphics/`, inlined as a data URI, and every number is read
from `data/fleet.json` and `data/ships.json` in the order
`src/sim/catalog.gd` merges them. If a hull looks wrong on this page, the
asset is wrong.

That is also why it does not duplicate the diorama page under CLAUDE.md 4.1.
The diorama draws its own icons because when it was written nothing else
could. This one cannot draw at all: it can only show what
`tools/gen_ship_graphics.py` wrote.

THE PAGE WEARS THE GAME'S OWN DECK. Its colours are the steel console skin,
resolved out of `data/palette.json` at build time, so a palette swap repaints
this page along with everything else (CLAUDE.md 3.1). Its faces are the pair
the diorama page already uses.

It is dark and has no light theme, deliberately rather than by omission: an
icon and an outline are white coverage masks on transparent, which is what
section 3.2 makes them so the screen drawing them picks the tint, and white on
a pale ground is an empty box.

Usage:
    python3 tools/gen_fleet_sheet.py

It writes the standalone page under docs/mockups and, beside it, the same
page without the document wrapper, which is the form the artifact host wants.
"""

import base64
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

ROOT = os.path.dirname(HERE)
GFX = os.path.join(ROOT, "assets", "graphics")
PALETTE = os.path.join(ROOT, "data", "palette.json")
OUT = os.path.join(ROOT, "docs", "mockups", "fleet-roster.html")
OUT_FRAGMENT = os.path.join(ROOT, "docs", "mockups", "fleet-roster.body.html")

## Which console skin the page wears. Steel is the cool institutional deck; the
## roster is an instrument rather than a bridge, so it takes the quieter one.
SKIN = "steel"

## The roles this page paints from, in the order they are written into CSS.
## Named rather than globbed so a skin growing a role does not silently grow
## the page a variable nobody uses.
ROLES = ("bg", "panel", "panel_2", "line", "line_hot", "fg", "dim",
         "accent", "accent_dim", "mark", "warn", "crit")

## data/factions.json says what a navy is called and in what order the navies
## are listed. This page reads it rather than keeping its own list, because
## that is the question src/sim/catalog.gd already answers for the screens and
## two answers would drift (CLAUDE.md 4.1 and 5.4).
FACTIONS = os.path.join(ROOT, "data", "factions.json")

## A one line gloss per culture, from docs/17. A heading names a thing and does
## not explain it (CLAUDE.md 6.5), but a roster of six cultures a reader may
## not have met is the case that clause is for, so each gets one line and no
## more.
FACTION_NOTE = {
    "terran": "Saucer forward, nacelles outboard.",
    "kthaari": "Swept wings, a raptor read from above.",
    "vaelith": "A ring, and a head on the centreline.",
    "sarn": "Faceted solids inside a belt.",
    "helion": "A spine with modules clamped to it.",
    "bloom": "Grown, not built.",
    "federation": "The hulls that predate the kit, still flown.",
}


def navies():
    """(name by id, id order), from the file the game reads for the same thing."""
    data = json.load(open(FACTIONS))
    names = {k: v["name"] for k, v in data["factions"].items()}
    return names, [str(i) for i in data["order"]]


def deck():
    """The steel skin's lit roles as hex, straight out of the palette file."""
    data = json.load(open(PALETTE))
    colors = dict(data["colors"])
    colors.update(data.get("ui_colors", {}))
    lit = data["ui_skins"][SKIN]["lit"]
    return {role: colors[lit[role]] for role in ROLES}


def data_uri(path):
    with open(path, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def hull_rows():
    """Every hull the game can load, generated first and hand authored after."""
    rows = []
    for name in ("fleet.json", "ships.json"):
        path = os.path.join(ROOT, "data", name)
        if not os.path.exists(path):
            continue
        for hull_id, h in json.load(open(path))["hulls"].items():
            stem = os.path.basename(h["mesh"])[:-4]
            art = {kind: os.path.join(GFX, "%s_%s.png" % (stem, kind))
                   for kind in ("schematic", "icon", "outline")}
            if not all(os.path.exists(p) for p in art.values()):
                print("no graphic set for %s, skipped" % hull_id)
                continue
            rows.append((hull_id, h, {k: data_uri(v) for k, v in art.items()}))
    return rows


STYLE = """<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Rajdhani:wght@500;600;700&family=IBM+Plex+Sans:wght@400;500&display=swap">
<style>
  /* One theme on purpose: the icons and outlines are white coverage masks on
     transparent, so a pale ground shows an empty box. Every colour is a role
     of the steel console deck in data/palette.json, pasted in at build time. */
__TOKENS__
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--fg);
         font: 400 14px/1.55 "IBM Plex Sans", system-ui, sans-serif; }

  header { padding: 26px 28px 20px; border-bottom: 1px solid var(--line); }
  .eyebrow { font-family: Rajdhani, system-ui, sans-serif; font-weight: 600;
             font-size: 12px; letter-spacing: .22em; text-transform: uppercase;
             color: var(--accent_dim); margin: 0 0 6px; }
  h1 { font-family: Rajdhani, system-ui, sans-serif; font-weight: 700;
       font-size: 30px; letter-spacing: .02em; margin: 0; text-wrap: balance; }
  header p { margin: 8px 0 0; max-width: 62ch; color: var(--dim);
             font-size: 13.5px; }

  .bar { display: flex; flex-wrap: wrap; align-items: center; gap: 22px;
         padding: 14px 28px; border-bottom: 1px solid var(--line);
         position: sticky; top: 0; background: var(--bg); z-index: 2; }
  .modes { display: flex; border: 1px solid var(--line_hot); border-radius: 2px;
           overflow: hidden; }
  .modes button { background: transparent; border: 0;
                  border-right: 1px solid var(--line_hot); color: var(--dim);
                  font-family: Rajdhani, system-ui, sans-serif; font-weight: 600;
                  font-size: 12.5px; letter-spacing: .14em;
                  text-transform: uppercase; padding: 7px 15px; cursor: pointer; }
  .modes button:last-child { border-right: 0; }
  .modes button[aria-pressed="true"] { background: var(--panel_2);
                                       color: var(--accent); }
  .modes button:focus-visible { outline: 2px solid var(--accent);
                                outline-offset: -2px; }
  .tally { display: flex; gap: 20px; font-family: Rajdhani, system-ui, sans-serif;
           font-weight: 600; font-size: 12px; letter-spacing: .16em;
           text-transform: uppercase; color: var(--dim); }
  .tally b { color: var(--fg); font-variant-numeric: tabular-nums; }

  main { padding: 6px 28px 40px; display: flex; flex-direction: column; gap: 34px; }
  section { display: flex; flex-direction: column; gap: 14px; }
  .head { display: flex; flex-wrap: wrap; align-items: baseline; gap: 14px;
          border-bottom: 1px solid var(--line); padding-top: 20px;
          padding-bottom: 8px; }
  h2 { font-family: Rajdhani, system-ui, sans-serif; font-weight: 700;
       font-size: 17px; letter-spacing: .12em; text-transform: uppercase;
       color: var(--accent); margin: 0; }
  .head span { color: var(--dim); font-size: 13px; }

  .grid { display: grid; gap: 12px;
          grid-template-columns: repeat(auto-fill, minmax(158px, 1fr)); }
  .cell { display: flex; flex-direction: column; gap: 2px; padding: 12px 12px 11px;
          height: 100%;
          background: var(--panel); border: 1px solid var(--line);
          border-radius: 2px; }
  .cell img { width: 100%; aspect-ratio: 1 / 1; display: block;
              margin-bottom: 8px; }
  .name { font-family: Rajdhani, system-ui, sans-serif; font-weight: 600;
          font-size: 16px; letter-spacing: .03em; color: var(--fg);
          line-height: 1.2; }
  .cls { color: var(--dim); font-size: 12px; }
  /* Pinned to the foot of the cell, so a name that wraps to two lines does not
     carry its hull's readings half a line below its neighbours'. */
  .foot { margin-top: auto; padding-top: 9px; }
  .figs { display: flex; align-items: baseline; justify-content: space-between;
          gap: 8px; margin-top: 7px; font-family: Rajdhani, system-ui, sans-serif;
          font-weight: 600; font-size: 12.5px; letter-spacing: .06em;
          font-variant-numeric: tabular-nums; color: var(--warn); }
  .figs em { font-style: normal; color: var(--dim); }
  /* The rung bar IS the class ladder: tonnage against the command tonnage cap,
     so a column of cells reads as the ladder it was generated from rather than
     as a column of numbers. */
  .rung { height: 2px; background: var(--line); }
  .rung i { display: block; height: 2px; background: var(--accent_dim); }

  footer { padding: 18px 28px 34px; border-top: 1px solid var(--line);
           color: var(--dim); font-size: 12.5px; max-width: 76ch; }
  code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: .92em;
         color: var(--mark); }
  @media (prefers-reduced-motion: no-preference) {
    .modes button { transition: color .12s ease, background-color .12s ease; }
  }
</style>"""

SCRIPT = """<script>
  const shots = [...document.querySelectorAll(".cell img")];
  document.getElementById("modes").addEventListener("click", (e) => {
    const hit = e.target.closest("button");
    if (!hit) return;
    for (const b of document.querySelectorAll("#modes button")) {
      b.setAttribute("aria-pressed", String(b === hit));
    }
    for (const img of shots) img.src = img.dataset[hit.dataset.mode];
  });
</script>"""


def build():
    rows = hull_rows()
    tokens = "\n".join("    --%s: %s;" % (r, c) for r, c in deck().items())
    style = STYLE.replace("__TOKENS__", "  :root {\n%s\n  }" % tokens)

    cap = int(json.load(open(os.path.join(ROOT, "data", "tuning.json")))
              ["skirmish"]["command_tonnage"])

    names, order = navies()
    by_faction = {}
    for hull_id, h, art in rows:
        by_faction.setdefault(h["faction"], []).append((hull_id, h, art))
    # Listed in the file's order, with anything it does not name kept and put
    # last, which is exactly what Catalog._in_data_order does for the screens.
    by_faction = {f: by_faction[f] for f in order if f in by_faction} | {
        f: g for f, g in by_faction.items() if f not in order}

    out = [style,
           "<title>Federation Fleet Roster</title>",
           '<header><p class="eyebrow">The Federation</p>',
           "<h1>Fleet Roster</h1>",
           "<p>Every hull the game can fly, with the three standard graphics it "
           "ships. Nothing on this page is drawn here: each image is a committed "
           "PNG written from the committed mesh, so what you see is what the "
           "ship systems display, the target readout and the map blip will "
           "show.</p></header>",
           '<div class="bar"><div class="modes" id="modes">'
           '<button data-mode="icon" aria-pressed="true">Icon</button>'
           '<button data-mode="outline" aria-pressed="false">Outline</button>'
           '<button data-mode="schematic" aria-pressed="false">Schematic</button>'
           "</div>",
           '<div class="tally"><span><b>%d</b> hulls</span>'
           "<span><b>%d</b> navies</span>"
           "<span>command cap <b>%d</b> t</span></div></div>"
           % (len(rows), len(by_faction), cap),
           "<main>"]

    for faction, group in by_faction.items():
        group.sort(key=lambda r: (int(r[1]["tonnage"]), r[1]["name"]))
        out.append('<section><div class="head"><h2>%s</h2><span>%s</span></div>'
                   '<div class="grid">'
                   % (names.get(faction, faction.capitalize()),
                      FACTION_NOTE.get(faction, "")))
        for hull_id, h, art in group:
            tons = int(h["tonnage"])
            out.append(
                '<div class="cell">'
                '<img src="%s" data-icon="%s" data-outline="%s" '
                'data-schematic="%s" alt="%s, seen from above">'
                '<span class="name">%s</span>'
                '<span class="cls">%s</span>'
                '<div class="foot"><div class="rung">'
                '<i style="width:%d%%"></i></div>'
                '<div class="figs"><span>%d t</span>'
                "<em>%d mounts</em></div></div></div>"
                % (art["icon"], art["icon"], art["outline"], art["schematic"],
                   h["name"], h["name"], h["cls"],
                   max(3, round(100.0 * tons / cap)), tons, len(h["mounts"])))
        out.append("</div></section>")

    out.append("</main>")
    out.append(
        "<footer>The bar under each name is that hull's tonnage against the "
        "skirmish command cap, so a column reads as the class ladder it was "
        "generated from. Icons and outlines are white coverage masks, shown "
        "here on the page ground; in game the screen drawing one picks the "
        "tint. Built by <code>tools/gen_fleet_sheet.py</code> from "
        "<code>assets/graphics/</code>, <code>data/fleet.json</code> and "
        "<code>data/ships.json</code>.</footer>")
    out.append(SCRIPT)
    return "\n".join(out), len(rows)


def main():
    page, count = build()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    # Two wrappers, one page. The committed mockup is a whole document because
    # it is opened as a file; the fragment is the same content without the
    # document tags, because the artifact host supplies those itself.
    with open(OUT_FRAGMENT, "w") as f:
        f.write(page + "\n")
    with open(OUT, "w") as f:
        f.write('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
                '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
                + page + "\n</head>\n<body></body>\n</html>\n")
    for path in (OUT, OUT_FRAGMENT):
        print("wrote %s (%d hulls, %.0f KB)"
              % (os.path.relpath(path, ROOT), count,
                 os.path.getsize(path) / 1024))


if __name__ == "__main__":
    main()
