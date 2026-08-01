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
(3C7), and reinforcement is paid from the same pool. Section 5 quotes both rules
in full. Power is the currency behind every system, which is why the power split
is a live decision rather than a fitting choice.

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
| Disabled box | Damaged box | Repairable during a battle, section 5 |
| Shield reinforcement | Reinforcement | Paid from the battery, `ShipState.reinforce` |
| Firing arc (FA, RS, LF) | Sector field | We use 12 sectors of 30 degrees, finer than the source |

Our arcs are finer than the source's. Federation Commander names arcs in words, we
give each mount a list of 30 degree sectors, which is what
`docs/02-ship-construction.md` describes and what the arc wheel draws. The six shield
facings are the coarse grid, the twelve firing sectors are the fine one, and each
facing is exactly two sectors wide.

---

## 5. Repair and shield regeneration

The source treats these as two completely separate systems, and says so. Shields are
bought back with energy, everything else is bought back with repair points, and
neither currency can pay for the other.

### 5.1 Shields cost energy

**(3C7) Shield regeneration**, quoted in full:

> "Shields can be regenerated. At the start of each turn, you can pay two Energy
> Tokens to regenerate (remove the disabled mark from) any one shield box on any one
> shield. You may do this for any number of shield boxes (up to the limit of Energy
> Tokens you have available). The shields are repaired immediately."

**(3C5) Shield reinforcement** is the other half of the same pool, and the rule that
explains why batteries matter:

> "Whenever a volley of damage strikes an active shield, the player who controls that
> ship has the option to use a number of his remaining Energy Tokens (up to the number
> of working batteries) to absorb some of the damage. Each Energy Token blocks one
> point of damage. Note that while batteries limit the amount of power used on any
> given volley, you can use that much power against every volley, even if you used it
> on a previous volley of the same or a different impulse."

Two things to notice. Regeneration is a **rate limited purchase, not a trickle**:
nothing comes back unless the player spends for it, and the price is fixed per box.
And the battery is a **throughput limit on reinforcement**, not a store that empties:
the same batteries can block that many points again on the next volley.

### 5.2 Everything else costs repair points

**(5G1) Damage control rating.** Every ship carries a rating, "which is two for either
cruiser," it is "not reduced by damage to the ship during combat," and "there is,
effectively, no limit on the number of repairs a ship can perform on itself (given
enough time)."

**(5G2) Repair points**, quoted in full:

> "Every turn, each ship generates a number of repair points equal to its Damage
> Control Rating. There is no energy cost for this."

**(5G3) Repair cost.** The price of a box depends on what kind of box it is:

| Points | Boxes |
|---|---|
| 4 | All weapons: phasers, photon torpedoes, disruptors, drone racks, anti-drone racks |
| 3 | All power systems: warp engine, impulse engine, reactor, battery |
| 2 | Most ship systems: tractor, transporter, laboratory, probe launcher, shuttle |
| 2 | Control systems: bridge, auxiliary control, flag bridge, emergency bridge |
| 1 | Hull boxes, cargo boxes |

And the line that keeps the two systems apart:

> "Shields have their own repair system and cannot be repaired by these rules."

**(5G4) Repair procedure.** Three constraints worth keeping:

> "Note that the cost is per box, not per item, so a 15-box warp engine would take 45
> repair points, not 3. Unused repair points cannot be carried over to the next turn.
> Points could be applied to start repair on a single box, with the repair points of
> the next turn used to finish (or at least work on) that box... A player must complete
> the repairs of the box he started repairing before spending repair points on other
> boxes."

So repair is a **queue with one job at a time**, funded by a per turn income that is
lost if unspent, and a big system is expensive in proportion to how big it is.

### 5.3 What we take, and where we differ

| Federation Commander | The Federation | Why |
|---|---|---|
| Regeneration costs 2 energy per shield box, player initiated | Same price, paid continuously out of the shield sink | Below |
| Free passive shield regeneration | Does not exist | We currently have one, and it contradicts 3C7 |
| Batteries cap reinforcement per volley, refill for the next | Same cap, per volley, not a store that drains | Below |
| Repair points per turn from a damage control rating | Spare parts, a finite stock carried by the ship | Below |
| No energy cost for repair | Same, repair costs parts and time, never reactor output | Keeps the two currencies separate as the source does |
| 4 / 3 / 2 / 2 / 1 points by box family | Same relative ordering, our own numbers | Their numbers are theirs, section 10 of `CLAUDE.md` |
| One box at a time, unused points lost | A queue the player orders, one job at a time | Below |

**Our shield regeneration is wrong today and this is the rule that says so.**
`data/tuning.json` carries `shield_regen_per_sec`, a free trickle that hands shields
back whether or not the player pays for them. Under 3C7 nothing comes back unpaid.
The fix is to make the shields sink buy boxes at a fixed price, which turns the power
split into the decision it is in the source: points spent holding the shields up are
points not spent shooting.

**Repair points become spare parts, and that is a real difference.** The source
regenerates repair capacity every turn forever, because a Federation Commander battle
is a scenario that ends. Ours is an MMO where a ship flies out, fights, and comes
home, so the interesting resource is one that runs out and has to be restocked at a
base. Spare parts are the per turn income replaced by a stock: same cost table, same
one job at a time, same "cannot repair shields," but a hold that empties.

**Continuous time replaces the turn, the same way it does everywhere else.** The
source's "at the start of each turn" and "during the Repair Phase" are both anchored
to a turn structure we do not have. A repair takes a number of seconds proportional
to the box cost, and shield regeneration is paid per box as the energy accrues,
rather than in a batch at a fixed moment.
