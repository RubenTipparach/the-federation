# The Fleet

How sixty hulls get from the design bible into the game, and what each piece of the
pipeline is allowed to decide.

Status: **built and committed**. `docs/17-starship-design-bible.md` says what the ships
are; this says how they exist.

---

## 1. What the fleet is

Six factions by ten classes. The factions are the five playable ones of `docs/GDD.md`
section 6 plus The Bloom, and the classes are the ladder of `docs/02-ship-construction.md`
section 2 with its three variants:

| | Frigate | Destroyer | Light cruiser | Heavy cruiser | Battlecruiser | Battleship | Dreadnought | Carrier | Freighter | Tender |
|---|---|---|---|---|---|---|---|---|---|---|
| Terran Concord | Swiftsure | Vigilant | Endeavour | Meridian | Bastion | Sovereign | Indomitable | Highwater | Longhaul | Cornerstone |
| Kthaari Dominion | Cutthroat | Ravener | Blackfang | Warhowl | Deathgrip | Ironclaw | Doomcaller | Bloodmoot | Spoilhauler | Bonesetter |
| Vaelith Ascendancy | Sable Wing | Quiet Hunter | Glass Feather | Pale Ascendant | Silent Crown | Verdant Throne | First Circle | Ten Thousand Eyes | Slow Tide | Mending Hand |
| Sarn Concordance | Flint Warden | Obsidian Ward | Amber Lattice | Third Accord | Copper Assize | Grand Concord | First Decree | Nine Gates | Tribute Line | Keystone |
| Helion Combine | Dockhand | Hard Bargain | Ledger | Freeport | Strikebreaker | Charter Prime | Foundry | Drop Yard | Deep Hold | Jury Rig |
| The Bloom | Tendril | Sporefall | Bloomlight | Rotwake | Pale Thicket | Mother Lobe | Deep Bloom | Seedhold | Full Crop | Scar Tissue |

The five named hulls were in `data/ships.json` before the fleet existed and are hand
tuned; the sixty generated ones are in `data/fleet.json`, written by
`tools/gen_ship_data.py` from the knobs in `data/fleet_rules.json`. Two files rather than
one because a generator that rewrote the hand authored five would reserialise them on
every run, and a reviewer could not tell a real change from a reformatting.
`src/sim/catalog.gd` loads both. Named or not, every one of them is built from
the same kit, so the Wayfarer is a Terran heavy cruiser rather than a special case.

The five hand authored hulls carry `faction` values from before the cultures were
named, so the three Terran ones say `federation`. That is left alone rather than
quietly corrected: the value is written into saved designs and recorded battles on
players' disks, and renaming it would strand them. Every screen groups by whatever
the field says, so those three list under a heading of their own.

---

## 2. Where the shapes live, and why not in the page

The diorama page built these ships in JavaScript so they could be reviewed. That was the
right place for a mockup and the wrong place for an asset: CLAUDE.md section 2 wants a
written `.obj` on disk, and section 4.1 refuses a second implementation of anything. So
the geometry moved:

    tools/shipkit.py        the primitives, the Hull, the atlas, the class ladder
    tools/fleet/parts.py    the parts every dialect shares: pod, pylon, crane, cannon
    tools/fleet/<faction>.py   one module per dialect, each exporting build(cls)
    tools/fleet/paint.py    the one painter that dresses all six atlases
    tools/gen_fleet.py      the driver that writes every asset

A faction module receives a row of the class ladder and returns a `Hull`. It decides
shape and nothing else: not size, not colour, not statistics. That separation is what
lets a dialect be rewritten without touching sixty hull entries, which happened three
times while the Kthaari, Vaelith and Sarn plans were being settled.

### 2.1 Three conventions

- **The bow is +Z.** The committed hulls already pointed that way and `hull_view.gd`
  frames a ship with +Z up the screen. The diorama page draws its bow at -Z, so a port
  from that source negates every z. It is the single most likely way to get a ship
  flying backwards.
- **Winding is computed, never asserted.** Every triangle's normal is its own cross
  product, taken at emit time. `shiplib.slab` had to warn about this in a comment
  because it built winding and normals separately; here they cannot disagree.
- **One world unit is twenty four texels.** Atlas rectangles are sized from that, so a
  plate is the same size on a pod, a wing and a hull.

---

## 3. One atlas per faction

Sixty hand painted atlases is not a thing anybody can maintain, and sixty hulls of six
cultures do not need sixty skins: the faction IS the paint. So each culture has one
atlas and its ten hulls share it.

`shipkit.ATLAS` gives a rectangle per part role and face direction. The roles are the
kit of parts of `docs/17` section 3, one entry each: disc, body, pod, wing, head, pylon,
ring, bay, truss, cargo, organic, greeble and glow. Four directions dress six, because a
hull is symmetric about its centreline and a top down game rarely shows an underside:
`top` also serves the bottom, `side` both flanks, `fore` the bow, `aft` the stern. A pod
adds `inner`, the flank it turns toward its twin, which is where the field grille goes.

The rectangles are **packed, not placed**. The first cut of the table was written by
hand and had three overlaps in it, which `shiplib.verify` would have reported as a
painting fault rather than a layout one. A shelf packer over a table of wanted sizes
cannot produce an overlap, so that class of bug is gone.

The grid is 256 logical, exported at 2x nearest like every other committed texture.
Larger than the 128 of a single hand painted hull (`docs/17` section 10) because ten
hulls share it, and a texel is still a chunk on screen.

---

## 4. What gets written

Per hull:

    assets/meshes/hull_<faction>_<class>.obj            the hull
    assets/meshes/hull_<faction>_<class>_frag_N.obj     eight pieces, for the wreck
    assets/meshes/hull_<faction>_<class>_wire.obj       the top down wireframe
    assets/graphics/hull_<faction>_<class>_schematic.png
    assets/graphics/hull_<faction>_<class>_icon.png
    assets/graphics/hull_<faction>_<class>_outline.png

Per faction:

    assets/textures/hull_<faction>_diffuse.png
    assets/textures/hull_<faction>_lights.png
    assets/textures/hull_<faction>_engines.png
    assets/materials/mat_hull_<faction>.tres

The fragment and wireframe names are a contract rather than a convention:
`ship_rig.gd` and `hull_view.gd` derive them from the hull's mesh path, so a hull does
not name them in `data/ships.json` and cannot get them wrong.

The three graphics are the standard set of CLAUDE.md section 3.2, written by
`tools/gen_ship_graphics.py` from the committed `.obj` so they cannot disagree with the
mesh.

---

## 5. Size is mostly not in the mesh

Every hull is normalised to about the same footprint, and the tactical view scales it by
tonnage (`ship_rig.gd`). A dreadnought is a big ship because it weighs three hundred
tons, not because its `.obj` is enormous. The mesh carries a small part of the story:
the ladder's footprint runs from 3.8 to 5.2 units, so a dreadnought is a little larger
before tonnage has said anything.

Normalisation is by the widest horizontal span rather than by length, because the
dialects disagree about which way a ship is long. A Terran frigate is a disc with pods
either side and is wider than it is deep; a Helion freighter is a spine. Fitting the
footprint puts them in the same box, which is what the tactical camera and the sixty
pixel silhouette both want.

---

## 6. The checks that run on every hull

- **One piece, twice measured.** `shiplib.Obj.write` refuses a hull that is more than
  one connected component or leaves more than one blob in its sixty pixel silhouette
  (CLAUDE.md section 2.1). `Hull.attachment()` runs the same test earlier and names the
  loose parts, so a builder is debugged by name instead of by a count. Between them they
  caught a floating freighter command hull, cargo pylons rooted in empty space and a
  tender's cranes hanging under its saucer.
- **Palette exact.** `shiplib.verify` refuses any painted pixel outside an atlas
  rectangle and any colour that is not a palette entry (section 3.1).
- **Committed meshes stay one piece.** `tools/check_hulls.py` runs both measures over
  everything in `assets/meshes/` so a hand edit in Blender is caught too.

---

## 7. Regenerating

    python3 tools/gen_fleet.py                  every asset for every hull
    python3 tools/gen_fleet.py --faction terran one culture
    python3 tools/gen_ship_graphics.py          the standard graphic set, section 3.2
    python3 tools/gen_ship_data.py              the sixty hull entries in data/fleet.json
    python3 tools/gen_ship_data.py --check      prove that file still matches its generator
    python3 tools/check_hulls.py                both one piece measures over the committed meshes
    ./scripts/run-tests.sh                      the suite, including the catalog checks

`gen_fleet.py` calls the graphics tool itself at the end of a run, so the third line is
only needed when a graphic changes without its mesh changing.

A palette swap is `data/palette.json` and then the first of those, which is the property
section 3.1 exists to buy.

---

## 8. What is deliberately not here

- **Per hull paint.** Ten hulls of a culture wear one skin. A registry number is a mark
  in the shared atlas rather than a per ship painting, so a Terran cruiser and a Terran
  carrier carry the same one. If a hull ever needs its own, it gets its own atlas the
  way `hull_ironhold` did, and nothing else changes.
- **The diorama's small greebles.** The page hangs about forty little meshes on a hull
  because a reviewer looks at it from close up. A tactical hull is sixty pixels across,
  so the generated meshes carry only the greebles that change an outline and leave the
  rest to the atlas. That is the difference between a thousand triangles and five.
- **A hull line per faction.** `docs/GDD.md` says hull lines progress by variant. The
  fleet is one hull per class per faction, which is the spine that variants will hang
  off, not the finished catalogue.
