#!/usr/bin/env python3
"""Writes data/fleet.json: the sim data for the sixty generated hulls.

WHY A SECOND CATALOG FILE.

data/ships.json holds five hand authored hulls, hand tuned and hand formatted.
A generator that rewrote that file would reserialise those five on every run,
and a reviewer would have no way to tell a real change from a reformatting. So
the generated fleet is its own file: ships.json is the hand authored catalog,
fleet.json is the generated one, and src/sim/catalog.gd loads both and merges
them. One loader, two sources, no hand editing of a build product.

WHERE THE NUMBERS COME FROM.

All of them from data/fleet_rules.json, which is the designer's file: per class
scalars, per faction dialect, the mount plans, the arcs, the box counts and the
names. Nothing tunable is written in this script (CLAUDE.md section 5.4).
Retune the fleet by editing the rules and running this again.

WHAT IT CHECKS, over all sixty hulls, before it writes anything:

  - tonnage climbs the ladder and the heaviest hull exactly fills the skirmish
    command tonnage cap in data/tuning.json
  - every budget leaves room for the bare hull, its default weapons, and a
    margin on top, so no hull opens red on the fitting screen
  - every default weapon exists in data/weapons.json, is a family its mount
    permits, and fits the mount's size
  - every mount is linked to exactly one internals entry and every internals
    entry names a real mount
  - every subsystem code has a committed icon in assets/icons
  - every hull's mesh and material are on disk

Usage:
    python3 tools/gen_ship_data.py            write data/fleet.json
    python3 tools/gen_ship_data.py --write    the same, said out loud
    python3 tools/gen_ship_data.py --check    regenerate and diff, write nothing
    python3 tools/gen_ship_data.py --report   the ladder and the budget margins
Exit: 0 clean, 1 on any failed check or, under --check, any difference.
"""

import argparse
import difflib
import glob
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import shipkit as kit                                            # noqa: E402

ROOT = os.path.dirname(HERE)
RULES_PATH = os.path.join(ROOT, "data", "fleet_rules.json")
WEAPONS_PATH = os.path.join(ROOT, "data", "weapons.json")
TUNING_PATH = os.path.join(ROOT, "data", "tuning.json")
SHIPS_PATH = os.path.join(ROOT, "data", "ships.json")
OUT_PATH = os.path.join(ROOT, "data", "fleet.json")
ICON_DIR = os.path.join(ROOT, "assets", "icons")

# The size ladder a mount enforces. It is stated in src/sim/fit.gd as well,
# because a Python tool cannot call GDScript and the alternative is a fleet
# nobody checks. This is a mirror rather than a second implementation: nothing
# here decides whether a weapon may be fitted at runtime, it only refuses to
# WRITE a default the game would then reject.
SIZE_RANK = {"Light": 0, "Medium": 1, "Heavy": 2, "Spinal": 3}

# The four budgets, in the order data/ships.json writes them. base_load calls
# power "power_draw" because it is a demand rather than a cap.
BUDGET_KEYS = ("space", "power", "mass", "crew")
LOAD_KEYS = {"space": "space", "mass": "mass", "crew": "crew", "power": "power_draw"}

# CLAUDE.md section 1 bans both dashes from every kind of text this repository
# writes, and a generated ship name is text. Named by codepoint, exactly as the
# rule itself is, so this file stays clean ASCII and scripts/check-style.sh does
# not report the checker.
EM_DASH = "\u2014"
EN_DASH = "\u2013"

SECTOR_COUNT = 12
FACING_COUNT = 6

HEADER = (
    "Generated hulls, sixty of them, six factions by ten classes. Written by "
    "tools/gen_ship_data.py from data/fleet_rules.json: do not hand edit, the "
    "next run would drop the edit. The schema is data/ships.json's, field for "
    "field, and src/sim/catalog.gd loads both files. Hand authored hulls live "
    "there; this file is a build product."
)
HEADER_RULES = (
    "Every number here comes from data/fleet_rules.json (CLAUDE.md 5.4): the "
    "per class ladder and the per faction dialect. Retune by editing that file "
    "and running the tool again. Run it with --check to prove this file still "
    "matches its generator."
)


def iround(x):
    """Round half up, so a rules file edit moves a number the way a designer
    expects. Python's own round() goes to even and would turn 2.5 into 2."""
    return int(math.floor(float(x) + 0.5))


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def facing_of_sector(sector):
    """Facing 0 (bow) is sectors {11, 0}, facing 1 is {1, 2}, and so on. The
    same mapping as src/sim/sectors.gd facing_of_sector."""
    return ((sector + 1) % SECTOR_COUNT) // 2


def facings_of(sectors):
    return set(facing_of_sector(s) for s in sectors)


def icon_stems():
    """The committed subsystem masks. src/ui/sys_line.gd builds the path as the
    code lowercased with its hyphens removed, so that is the test."""
    return set(os.path.basename(p)[:-4]
               for p in glob.glob(os.path.join(ICON_DIR, "*.png")))


def code_icon(code):
    return code.lower().replace("-", "")


# ------------------------------------------------------------------ building --


def split_boxes(total, facings):
    """Spread one system's boxes over the facings it lives behind. Two facings
    is what makes the warp drive two nacelles rather than one block; an odd
    count leans forward, which is where the machinery is."""
    if len(facings) == 1:
        return [(facings[0], total)]
    out = []
    left = total
    for i, f in enumerate(facings):
        take = int(math.ceil(left / float(len(facings) - i)))
        if take > 0:
            out.append((f, take))
        left -= take
    return out


def scaled_boxes(count, scale):
    """A faction's box count for a system. A scale of 0 removes the system, and
    anything else keeps at least one box: a culture with fewer marines still
    has marines."""
    if scale == 0:
        return 0
    return max(1, iround(count * scale))


def build_hull(rules, weapons, faction_id, cls_id):
    cls = rules["classes"][cls_id]
    fac = rules["factions"][faction_id]
    sysscale = fac.get("system_scale", {})

    # -- mounts, and the weapon boxes that come with them ---------------------
    mounts = []
    weapon_rows = [[] for _ in range(FACING_COUNT)]
    for i, slot in enumerate(cls["mounts"]):
        mount_id = "M%d" % (i + 1)
        arc = rules["arcs"][slot["arc"]]
        role = fac["roles"][slot["role"]]
        default = role["default"]
        mounts.append({
            "id": mount_id,
            "pos": slot["pos"],
            "size": slot["size"],
            "families": list(role["families"]),
            "field": list(arc["sectors"]),
            "default": default,
        })
        boxes = rules["weapon_boxes"][default] + int(cls.get("weapon_box_bonus", 0))
        weapon_rows[arc["facing"]].append(
            [weapons[default]["short"], boxes, "weapon", mount_id])

    # -- support systems ------------------------------------------------------
    support_rows = [[] for _ in range(FACING_COUNT)]
    for code in rules["code_order"]:
        if code not in cls["systems"]:
            continue
        boxes = scaled_boxes(cls["systems"][code], sysscale.get(code, 1.0))
        if boxes == 0:
            continue
        family = rules["systems"][code]["family"]
        for facing, n in split_boxes(boxes, rules["placement"][code]):
            support_rows[facing].append([code, n, family])

    sectors = [weapon_rows[f] + support_rows[f] for f in range(FACING_COUNT)]

    core = []
    for code, count in cls["core"].items():
        boxes = scaled_boxes(count, sysscale.get(code, 1.0))
        if boxes > 0:
            core.append([code, boxes, rules["systems"][code]["family"]])

    # -- budgets, and the bare hull's share of them ---------------------------
    budgets = {}
    base_load = {}
    for key in BUDGET_KEYS:
        cap = iround(cls["budgets"][key] * fac["budget_scale"][key])
        budgets[key] = cap
        base_load[LOAD_KEYS[key]] = iround(
            cap * cls["base_load_fraction"][key] * fac["base_load_scale"][key])
    # ships.json writes base_load in space, mass, crew, power_draw order.
    base_load = {k: base_load[k] for k in ("space", "mass", "crew", "power_draw")}

    word = rules["note_mount_word"]["one" if len(mounts) == 1 else "many"]
    note = "%s %s %d %s." % (cls["note"], fac["note"], len(mounts), word)

    return {
        "name": fac["names"][cls_id],
        "cls": cls["display"],
        "tonnage": cls["tonnage"],
        "faction": faction_id,
        "playable": True,
        "ai": True,
        "note": note,
        "mesh": rules["mesh_path"].format(faction=faction_id, cls=cls_id),
        "material": rules["material_path"].format(faction=faction_id, cls=cls_id),
        "cargo_space": iround(cls["cargo_space"] * fac["cargo_scale"]),
        "damage_control": max(1, iround(cls["damage_control"]
                                        * fac["damage_control_scale"])),
        "spare_parts": max(1, iround(cls["spare_parts"] * fac["spare_parts_scale"])),
        "budgets": {k: budgets[k] for k in BUDGET_KEYS},
        "base_load": base_load,
        "shield_per_facing": iround(cls["shield_per_facing"] * fac["shield_scale"]),
        "max_speed": round(cls["max_speed"] * fac["speed_scale"], 1),
        "accel": round(cls["accel"] * fac["accel_scale"], 1),
        "turn_rate_deg": round(cls["turn_rate_deg"] * fac["turn_scale"], 1),
        "mounts": mounts,
        "internals": {"sectors": sectors, "core": core},
    }


def build_fleet(rules, weapons):
    """Sixty hulls, in faction order and within a faction in the shipkit CLASSES
    ladder order, so the file reads like the roster page."""
    out = {}
    for faction_id in kit.FACTIONS:
        for cls in kit.CLASSES:
            out["%s_%s" % (faction_id, cls["id"])] = build_hull(
                rules, weapons, faction_id, cls["id"])
    return out


# ---------------------------------------------------------------- validation --


class Failures(object):
    """Every failed check, gathered rather than raised, because a designer who
    has just retuned the rules file wants the whole list, not the first line."""

    def __init__(self):
        self.items = []

    def check(self, ok, message):
        if not ok:
            self.items.append(message)
        return ok

    def report(self):
        for m in self.items:
            print("FAIL: %s" % m, file=sys.stderr)
        return len(self.items)


def weapon_cost(weapons, hull, key):
    """What the hull's default weapons take out of one budget."""
    total = 0
    for m in hull["mounts"]:
        total += weapons[m["default"]]["costs"][LOAD_KEYS[key]]
    return total


def headroom(weapons, hull, key):
    return (hull["budgets"][key] - hull["base_load"][LOAD_KEYS[key]]
            - weapon_cost(weapons, hull, key))


def validate(rules, weapons, tuning, hulls, hand_hulls, fail):
    icons = icon_stems()
    cap = int(tuning["skirmish"]["command_tonnage"])
    ladder = rules["ladder"]

    # -- the rules file still describes the kit -------------------------------
    fail.check(sorted(ladder) == sorted(c["id"] for c in kit.CLASSES),
               "fleet_rules ladder is not the shipkit CLASSES set")
    keyed = [kit.CLASS_BY_ID[c] for c in ladder]
    for a, b in zip(keyed, keyed[1:]):
        fail.check((a["size"], a["foot"]) < (b["size"], b["foot"]),
                   "ladder is not sorted by shipkit size then foot: %s before %s"
                   % (a["id"], b["id"]))
    for cls_id, cls in rules["classes"].items():
        fail.check(cls["display"].lower() == kit.CLASS_BY_ID[cls_id]["name"].lower(),
                   "class display name disagrees with shipkit: %s" % cls_id)
    fail.check(list(rules["factions"]) == list(kit.FACTIONS),
               "fleet_rules factions are not the shipkit FACTIONS")

    # -- the tables the hulls are assembled from agree with each other --------
    fam_rank = {"power": 0, "control": 1, "hull": 2}
    ranks = [fam_rank[rules["systems"][c]["family"]] for c in rules["code_order"]]
    fail.check(ranks == sorted(ranks),
               "code_order must run power, then control, then hull: that is the "
               "order a facing is listed in and the order the display reads")
    for code in rules["code_order"]:
        fail.check(code in rules["systems"], "code_order names %r, which is not "
                   "a system" % code)
        fail.check(code in rules["placement"], "code_order names %r and nothing "
                   "says which facing it sits behind" % code)
    for cls_id, cls in rules["classes"].items():
        for code in cls["systems"]:
            fail.check(code in rules["code_order"],
                       "%s carries %r and code_order does not list it"
                       % (cls_id, code))
        for slot in cls["mounts"]:
            fail.check(slot["arc"] in rules["arcs"],
                       "%s has a mount on an unknown arc %r" % (cls_id, slot["arc"]))
            fail.check(slot["size"] in SIZE_RANK,
                       "%s has a mount of unknown size %r" % (cls_id, slot["size"]))
            for fac_id, fac in rules["factions"].items():
                fail.check(slot["role"] in fac["roles"],
                           "%s wants a %r mount and %s has no such role"
                           % (cls_id, slot["role"], fac_id))
    for fac_id, fac in rules["factions"].items():
        fail.check(sorted(fac["names"]) == sorted(rules["classes"]),
                   "%s does not name exactly one ship per class" % fac_id)
        fail.check(len(set(fac["names"].values())) == len(fac["names"]),
                   "%s uses a name twice" % fac_id)

    # -- the arcs are honest about which facing they sit behind ---------------
    for name, arc in rules["arcs"].items():
        secs = arc["sectors"]
        fail.check(len(set(secs)) == len(secs), "arc %s repeats a sector" % name)
        fail.check(all(0 <= s < SECTOR_COUNT for s in secs),
                   "arc %s has a sector outside 0..11" % name)
        fail.check(arc["facing"] in facings_of(secs),
                   "arc %s sits behind facing %d, which it cannot fire into"
                   % (name, arc["facing"]))

    fail.check(len(hulls) == len(kit.FACTIONS) * len(kit.CLASSES),
               "expected sixty hulls, got %d" % len(hulls))

    # -- tonnage: one ladder, and the top of it is the command cap ------------
    heaviest = max(h["tonnage"] for h in hulls.values())
    fail.check(heaviest == cap,
               "heaviest hull is %d, command_tonnage is %d" % (heaviest, cap))
    for faction_id in kit.FACTIONS:
        rung = [hulls["%s_%s" % (faction_id, c)]["tonnage"] for c in ladder]
        for i in range(1, len(rung)):
            fail.check(rung[i] > rung[i - 1],
                       "%s tonnage does not climb: %s %d then %s %d"
                       % (faction_id, ladder[i - 1], rung[i - 1], ladder[i], rung[i]))
        fail.check(hulls["%s_dreadnought" % faction_id]["tonnage"] == cap,
                   "%s dreadnought does not fill the command cap" % faction_id)
        fail.check(min(rung) == hulls["%s_frigate" % faction_id]["tonnage"],
                   "%s frigate is not the lightest hull" % faction_id)

    for hull_id, h in hulls.items():
        _validate_hull(rules, weapons, icons, cap, hull_id, h, fail)

    # -- the merged catalog stays unambiguous ---------------------------------
    for hull_id in hulls:
        fail.check(hull_id not in hand_hulls,
                   "hull id %s already exists in data/ships.json" % hull_id)
    names = {}
    for hull_id, h in list(hand_hulls.items()) + list(hulls.items()):
        fail.check(h["name"] not in names,
                   "two hulls are called %r: %s and %s"
                   % (h["name"], names.get(h["name"], ""), hull_id))
        names[h["name"]] = hull_id


def _validate_hull(rules, weapons, icons, cap, hull_id, h, fail):
    where = hull_id

    fail.check(h["tonnage"] <= cap,
               "%s is %d tons, over the command cap" % (where, h["tonnage"]))
    fail.check(h["playable"] and h["ai"],
               "%s must be both playable and ai" % where)
    for key in ("mesh", "material"):
        path = os.path.join(ROOT, h[key].replace("res://", ""))
        fail.check(os.path.exists(path), "%s names a missing %s: %s"
                   % (where, key, h[key]))
    for text in (h["name"], h["note"], h["cls"]):
        fail.check(EM_DASH not in text and EN_DASH not in text,
                   "%s has an em or en dash in its text" % where)

    # -- budgets ---------------------------------------------------------------
    for key in BUDGET_KEYS:
        cap_v = h["budgets"][key]
        base = h["base_load"][LOAD_KEYS[key]]
        fail.check(base < cap_v, "%s base_load %s is %d of a %d budget"
                   % (where, key, base, cap_v))
        room = cap_v - base
        cost = weapon_cost(weapons, h, key)
        margin = max(rules["min_headroom_absolute"],
                     iround(cap_v * rules["min_headroom_fraction"]))
        fail.check(room - cost >= margin,
                   "%s %s: %d free after the bare hull, default weapons cost "
                   "%d, leaving %d and the rules want %d"
                   % (where, key, room, cost, room - cost, margin))

    # -- mounts ---------------------------------------------------------------
    ids = [m["id"] for m in h["mounts"]]
    fail.check(len(set(ids)) == len(ids), "%s repeats a mount id" % where)
    for m in h["mounts"]:
        w = weapons.get(m["default"])
        if not fail.check(w is not None, "%s mount %s defaults to an unknown "
                          "weapon %r" % (where, m["id"], m["default"])):
            continue
        fail.check(w["family"] in m["families"],
                   "%s mount %s defaults to a %s, which its families %s do not "
                   "permit" % (where, m["id"], w["family"], m["families"]))
        fail.check(SIZE_RANK[w["size"]] <= SIZE_RANK[m["size"]],
                   "%s mount %s is %s and its default weapon is %s"
                   % (where, m["id"], m["size"], w["size"]))
        fail.check(len(m["field"]) > 0, "%s mount %s fires nowhere"
                   % (where, m["id"]))
        fail.check(len(set(m["field"])) == len(m["field"]),
                   "%s mount %s repeats a sector" % (where, m["id"]))
        fail.check(all(0 <= s < SECTOR_COUNT for s in m["field"]),
                   "%s mount %s has a sector outside 0..11" % (where, m["id"]))

    # -- internals -------------------------------------------------------------
    sectors = h["internals"]["sectors"]
    fail.check(len(sectors) == FACING_COUNT,
               "%s has %d shield facings, not six" % (where, len(sectors)))
    fail.check(len(h["internals"]["core"]) > 0, "%s has no hull core" % where)
    linked = []
    for entry in [e for rows in sectors for e in rows] + h["internals"]["core"]:
        code, boxes, family = entry[0], entry[1], entry[2]
        fail.check(code in rules["systems"] or _is_weapon_code(weapons, code),
                   "%s carries an unknown subsystem code %r" % (where, code))
        fail.check(code_icon(code) in icons,
                   "%s carries code %r and assets/icons/%s.png does not exist"
                   % (where, code, code_icon(code)))
        fail.check(boxes >= 1, "%s has a %s box count of %d" % (where, code, boxes))
        fail.check(family in ("weapon", "power", "control", "hull"),
                   "%s has a %s in family %r" % (where, code, family))
        if len(entry) > 3:
            linked.append(entry[3])
            fail.check(entry[3] in ids, "%s links a box to mount %s, which it "
                       "does not have" % (where, entry[3]))
    for mount_id in ids:
        fail.check(linked.count(mount_id) == 1,
                   "%s mount %s appears in %d internals entries, not one"
                   % (where, mount_id, linked.count(mount_id)))
    for entry in [e for rows in sectors for e in rows]:
        if entry[2] == "weapon":
            fail.check(len(entry) > 3, "%s has a weapon box %s with no mount"
                       % (where, entry[0]))


def _is_weapon_code(weapons, code):
    return any(w["short"] == code for w in weapons.values())


# ------------------------------------------------------------------ rendering --


def dump(value):
    return json.dumps(value, ensure_ascii=False)


def inline(d):
    """A one line object in the shape data/ships.json writes them: braces with
    a space inside, so a budget block reads as one row."""
    return "{ %s }" % ", ".join("%s: %s" % (dump(k), dump(v)) for k, v in d.items())


def render(hulls):
    out = ["{"]
    out.append('  "_comment": %s,' % dump(HEADER))
    out.append('  "_rules": %s,' % dump(HEADER_RULES))
    out.append('  "hulls": {')
    ids = list(hulls)
    for n, hull_id in enumerate(ids):
        h = hulls[hull_id]
        out.append('    %s: {' % dump(hull_id))
        out.append('      "name": %s, "cls": %s, "tonnage": %s, "faction": %s, '
                   '"playable": %s, "ai": %s,'
                   % (dump(h["name"]), dump(h["cls"]), dump(h["tonnage"]),
                      dump(h["faction"]), dump(h["playable"]), dump(h["ai"])))
        out.append('      "note": %s,' % dump(h["note"]))
        out.append('      "mesh": %s,' % dump(h["mesh"]))
        out.append('      "material": %s,' % dump(h["material"]))
        out.append('      "cargo_space": %s,' % dump(h["cargo_space"]))
        out.append('      "damage_control": %s, "spare_parts": %s,'
                   % (dump(h["damage_control"]), dump(h["spare_parts"])))
        out.append('      "budgets": %s,' % inline(h["budgets"]))
        out.append('      "base_load": %s,' % inline(h["base_load"]))
        out.append('      "shield_per_facing": %s,' % dump(h["shield_per_facing"]))
        out.append('      "max_speed": %s, "accel": %s, "turn_rate_deg": %s,'
                   % (dump(h["max_speed"]), dump(h["accel"]),
                      dump(h["turn_rate_deg"])))
        out.append('      "mounts": [')
        for i, m in enumerate(h["mounts"]):
            out.append("        %s%s" % (inline(m),
                                         "" if i == len(h["mounts"]) - 1 else ","))
        out.append("      ],")
        out.append('      "internals": {')
        out.append('        "sectors": [')
        rows = h["internals"]["sectors"]
        for i, row in enumerate(rows):
            out.append("          %s%s" % (dump(row),
                                           "" if i == len(rows) - 1 else ","))
        out.append("        ],")
        out.append('        "core": %s' % dump(h["internals"]["core"]))
        out.append("      }")
        out.append("    }%s" % ("" if n == len(ids) - 1 else ","))
    out.append("  }")
    out.append("}")
    return "\n".join(out) + "\n"


# --------------------------------------------------------------------- report --


def report(rules, weapons, hulls):
    ladder = rules["ladder"]
    print("TONNAGE LADDER (identical for every faction, see fleet_rules _tonnage)")
    for cls_id in ladder:
        h = hulls["terran_%s" % cls_id]
        print("  %-14s %4d t   shields %3d   speed %5.1f   %d mounts"
              % (cls_id, h["tonnage"], h["shield_per_facing"], h["max_speed"],
                 len(h["mounts"])))
    print()
    print("BUDGET HEADROOM, free after the bare hull and its default weapons")
    print("  %-22s %-14s %-14s %-14s %-14s"
          % ("hull", "space", "power", "mass", "crew"))
    worst = {}
    for hull_id, h in hulls.items():
        cells = []
        for key in BUDGET_KEYS:
            free = headroom(weapons, h, key)
            pct = 100.0 * free / float(h["budgets"][key])
            cells.append("%4d (%4.1f%%)" % (free, pct))
            if key not in worst or pct < worst[key][0]:
                worst[key] = (pct, free, hull_id)
        print("  %-22s %s" % (hull_id, "  ".join(cells)))
    print()
    print("TIGHTEST BUDGET PER AXIS")
    for key in BUDGET_KEYS:
        pct, free, hull_id = worst[key]
        print("  %-6s %s: %d free, %.1f%% of the cap" % (key, hull_id, free, pct))


# ----------------------------------------------------------------------- main --


def main(argv=None):
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true",
                    help="write data/fleet.json (the default)")
    ap.add_argument("--check", action="store_true",
                    help="regenerate in memory and diff against the committed file")
    ap.add_argument("--report", action="store_true",
                    help="print the tonnage ladder and the budget margins")
    args = ap.parse_args(argv)

    rules = load_json(RULES_PATH)
    weapons = load_json(WEAPONS_PATH)["weapons"]
    tuning = load_json(TUNING_PATH)
    hand_hulls = load_json(SHIPS_PATH)["hulls"]

    hulls = build_fleet(rules, weapons)

    fail = Failures()
    validate(rules, weapons, tuning, hulls, hand_hulls, fail)
    if fail.report():
        print("%d checks failed, nothing written" % len(fail.items), file=sys.stderr)
        return 1

    text = render(hulls)
    # Parsing what we are about to commit, so a formatting bug cannot ship a
    # file the game would fail to load.
    assert json.loads(text)["hulls"].keys() == hulls.keys()

    if args.report:
        report(rules, weapons, hulls)

    if args.check:
        if not os.path.exists(OUT_PATH):
            print("FAIL: %s does not exist" % OUT_PATH, file=sys.stderr)
            return 1
        with open(OUT_PATH, encoding="utf-8") as f:
            have = f.read()
        if have != text:
            sys.stderr.writelines(difflib.unified_diff(
                have.splitlines(True), text.splitlines(True),
                fromfile="data/fleet.json", tofile="regenerated"))
            print("FAIL: data/fleet.json does not match its generator",
                  file=sys.stderr)
            return 1
        print("PASS: data/fleet.json matches tools/gen_ship_data.py "
              "(%d hulls)" % len(hulls))
        return 0

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        f.write(text)
    print("wrote data/fleet.json: %d hulls, %d checks passed"
          % (len(hulls), len(hulls) * len(BUDGET_KEYS)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
