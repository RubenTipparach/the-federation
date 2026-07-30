# 09. Reference: Federation Commander

The combat model in this project is descended from Federation Commander, the game
the prototype's ship systems display is modelled on. This file records what the
source actually says, so design decisions cite a rule instead of a memory.

**Primary source:** *Federation Commander: First Missions*, Amarillo Design Bureau,
free rulebook PDF: https://www.starfleetgames.com/fc/FCFirstMissions.pdf

First Missions is the free starter rulebook. It is the abridged version: it teaches
the system with one ship class per empire and deliberately simplifies the damage
allocation procedure that the full game (*Klingon Border*) handles with dice and a
chart. Both versions are useful here, and the differences matter, so they are called
out below.

This is a reference for our own design work. Nothing here is copied into the game:
rules text, ship statistics, and artwork belong to Amarillo Design Bureau. What we
take is the shape of the system, the same way any tactical game inherits from its
ancestors.

---

## 1. What the source says

Section numbers are the rulebook's own.

**(3C1) Shield numbers.** "Each ship is surrounded by six shields, with #1 to the
front of the ship, #2 and #3 on the right (starboard) side, #4 to the rear, and #5
and #6 to the left (port) side."

**(3C2) Shields can be down or dropped.** Down means reduced to zero by damage.
Dropped means voluntarily deactivated, which the full game uses for transporter
operations.

**(3C3) Position.** Shields are fixed to the ship and each absorbs damage from the
direction it faces. Five boxes may be transferred from one shield to an adjacent
shield, and only to replace disabled boxes, never to exceed the original strength.

**(3D) Damage allocation.** "Once damage has struck the ship, it is first applied to
the single facing shield. Each point of damage disables one box of that shield.
Disabled shield boxes do not stop further damage. If there are more points of damage
than the strength of the shield, the remaining damage is scored on the inside of the
ship, with one damage point disabling one box on the ship card."

How that remainder is assigned is the one place the two versions differ. First
Missions lets the owning player mark any non-shield box they choose, and says plainly
why: "Tough choices await! Will you preserve power to move or weapons to shoot?"
*Klingon Border* replaces that choice with die rolls against a damage allocation
chart.

**(3E) How ships are lost.** A ship is destroyed "whenever all non-shield boxes of
the ship are marked disabled at any point during the turn." Destruction is described
as rare: damaged ships normally withdraw.

**(5J) Hull damage.** Hull boxes are nonessential volume, "crew quarters, the mess
hall, storage areas, and the bowling alley," and they exist to be padding that
absorbs damage which would otherwise destroy something that matters. The note that
settles our own question: in *Klingon Border* "hull damage is subdivided into forward
and rear sections for the damage allocation system," which First Missions omits for
simplicity.

**Energy.** Shield regeneration costs two energy tokens per shield box repaired
(3C7). Reinforcement is paid from the same pool. Power is the currency behind every
system, which is why the power split is a live decision rather than a fitting choice.

---

## 2. What we take, and where we differ

| Federation Commander | The Federation | Why |
|---|---|---|
| Six shields, #1 forward, numbered clockwise | Same, six facings numbered 1 to 6 from the bow | Identical, including the numbering direction |
| Shield absorbs first, remainder goes inside | Same | `ShipState.apply_damage` |
| Owner picks the box (First Missions), or dice and a chart (Klingon Border) | Struck sector first, then the hull core | Below |
| Hull boxes as padding, split fore and aft in the full game | Hull core as one shared block, taking everything a stripped sector cannot | Below |
| Impulse based turn structure, energy allocation each turn | Continuous real time with a live power split | This is a real time game, not a turn based one |
| Ship lost when every non-shield box is disabled | Same | `ShipState.alive` |

**Where the remainder lands is our own decision, and it is deliberate.** Neither
source rule fits a real time game: letting the player choose the box needs a paused
turn, and a die roll chart hides the geometry that our display is built to show. Our
rule is that bleed through damages the systems in the facing it arrived through, and
when that sector has no boxes left the hull core takes the rest. It generalises the
full game's fore and aft hull split from two sections to six, and it makes the
display and the model say the same thing: what you see behind a shield is what dies
when that shield falls.

---

## 3. Weapons and range

The source's weapon charts are the part worth inheriting. Every direct fire weapon has a
table indexed by range, and the three archetypes behave differently as the range grows.

**Phasers (charts on page 19).** One die per shot, cross indexed against a range column.
The damage in the table shrinks as range grows, but a phaser at extreme range still scores
something on a good roll: it never stops connecting, it stops mattering. Phaser-1 is the
heavy mount, Phaser-2 the medium, Phaser-3 the short ranged defensive one, and each has its
own table.

**Photon torpedoes (chart on page 20, arming in 4C).** Damage is flat across the whole
range column. What changes is the "to hit" number: near certain up close, a single number
on the die at maximum range. A torpedo is all or nothing, and the decision it forces is
whether to hold the shot for a closer pass, which the arming rules (4C5) make expensive.

**Disruptors (chart on page 20, procedure in 4D2).** Both rows shrink: accuracy falls and
so does the damage per hit. The result is a weapon that punishes long range trades from
both directions.

**What we take.** The three shapes, exactly as above. Beams hold accuracy and lose damage,
torpedoes hold damage and lose accuracy, disruptors lose both. Our version replaces the
die roll with a hit chance per band, since a real time game resolves shots continuously
rather than once per impulse, and a probability is the same statement without a turn
structure to hang it on.

**What we do not take.** Their numbers. Our bands are in our own distance units and tuned
against our own hulls, and they live in `data/weapons.json` where a designer can change
them. Copying the published tables would be copying the game, not learning from it, per
section 10 of `CLAUDE.md`.

The shared reader is `src/sim/weapon_model.gd`. Nothing else in the codebase interprets a
band, so the fitting screen's projection and a live shot cannot drift apart.

---

## 4. Terms

| Source term | Ours | Note |
|---|---|---|
| Ship card, SSD | Ship systems display | Same object: the diagram carrying every box |
| Box | Box | One hit point of one system |
| Disabled box | Destroyed box | We do not model repair during a battle yet |
| Shield reinforcement | Reinforcement | Paid from the battery, `ShipState.reinforce` |
| Firing arc (FA, RS, LF) | Sector field | We use 12 sectors of 30 degrees, finer than the source |

Our arcs are finer than the source's. Federation Commander names arcs in words, we
give each mount a list of 30 degree sectors, which is what
`docs/02-ship-construction.md` describes and what the arc wheel draws. The six shield
facings are the coarse grid, the twelve firing sectors are the fine one, and each
facing is exactly two sectors wide.
