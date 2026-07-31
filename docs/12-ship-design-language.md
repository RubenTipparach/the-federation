# 12. Ship design language

How the ships in Starfleet Command are put together, and what our hulls take from
that. This is a reference for making our own ships legible, not a licence to copy
theirs.

**Sources looked at:** the fan and archive models of Starfleet Command era ships
published on Sketchfab, in particular SquireJames' Ark Royal class fleet carrier,
Type CVN-VI fleet carrier, and Type DN-III dreadnought
(https://sketchfab.com/3d-models/ark-royal-class-fleet-carrier-c6c4d294ac1243b1ad7bcb80e34a88c8
and the same author's other uploads). Those models are not downloadable and carry
no licence, and they descend from Star Trek and from Starfleet Command II assets.
Nothing from them is in this repository. What follows is observation of the design
grammar, which is what CLAUDE.md section 10 permits: take the shape of the system,
never the assets.

---

## 1. Three parts, recombined

Every ship in that tradition is assembled from the same three kinds of volume:

| Part | What it is | What it says |
|---|---|---|
| **Primary hull** | The big command volume: a disc, a wedge, or a block | Which empire built it |
| **Secondary hull** | The spine or engineering body behind and below it | How much ship there is |
| **Propulsion pods** | Nacelles or drive blocks, always paired, held outboard on pylons | How fast, and how big |

No class introduces a fourth kind of part. A carrier is not a different vocabulary
from a cruiser: it is the same three parts in different proportion. That is why an
unfamiliar ship still reads as belonging to its empire.

---

## 2. Empire is proportion and angle, not detail

**Federation.** A circular primary hull, dominant, often half the ship's length and
its widest single element. Everything is horizontal and rounded. Nacelles sit
behind and outboard, above the plane of the saucer. The overall gesture is a disc
towing its engines.

**Everyone else.** The primary hull becomes a wedge or a delta pointed at the enemy.
The wings sweep back and drop below the plane. Pods move to the wingtips. The mass
migrates aft, and the bow narrows. The gesture is a bird of prey rather than a
platform.

Both of the non Federation ships I looked at share that: a narrow forward point, a
wide swept span, engine blocks at the outboard trailing corners, and a body that
is deepest at the back. Ours does the same, which is why `hull_raider` reads as
hostile next to `hull_cruiser` without any paint.

---

## 3. Scale is part count, not size

A frigate and a dreadnought are not the same silhouette scaled up. Size is
communicated by **adding parts**:

- Frigate: short spine, two pods, no separate secondary hull.
- Cruiser: full spine, two pods, distinct secondary hull.
- Dreadnought or carrier: **four pods** in stacked pairs, or a doubled secondary
  hull, or both.

The Ark Royal makes the point: four nacelles in two stacked pairs, mounted high
and far outboard. From any angle, doubling the pods says "capital" faster than any
amount of extra length.

**For us:** when we add a carrier or a dreadnought, the change is four pods and a
longer spine, not a bigger version of `hull_cruiser`. Tonnage already scales the
draw size, so silhouette has to carry class.

---

## 4. The top down read is the whole constraint

Starfleet Command is played from a high three quarter view, and our tactical camera
is clamped to look down. That single fact explains most of these design decisions:

- Pods project far outboard because **width is what the top down view sees**. A
  ship whose distinguishing feature is vertical is unidentifiable in play.
- The bow is a point or a narrowing, so heading is readable at a glance without a
  marker.
- Nothing important lives under the hull, because it is never visible.

**Our rule, and it is not optional:** a class must be identifiable from directly
above at roughly 60 pixels. If two hulls are only distinguishable in a side view,
one of them is not doing its job.

---

## 5. Detail is texture, not geometry

The archive models are between 400 and 1,200 triangles. The Ark Royal is 556 faces
and 342 vertices. Everything that makes them look complicated is painted on:
windows, plating seams, registry numbers, warp grilles, and the glowing strips.

That is the most directly useful lesson. Our generated hulls are 376 and 512
triangles, already in the same band, and the right move when they start to look
plain is **a texture pass, not a subdivision pass**. Geometry buys silhouette;
texture buys everything else. Per CLAUDE.md section 3 those maps ship as committed
`.png` files.

---

## 6. Light says which way it is pointing

In every one of those models the lighting is doing navigational work: cool white
and blue toward the bow and along the leading edges, hot red and amber at the drive
ends. Even in a dark scene at small scale, the ship's facing reads from where the
warm light is.

We get this for free today because the tactical view tints whole hulls by
allegiance, but it is worth keeping when hull textures arrive: **warm aft, cool
forward**, so a player can read a heading from the colour before they read the
model.

---

## 7. What this means for our hulls

| Ours | Follows | Would change if |
|---|---|---|
| `hull_cruiser` | Federation grammar: dominant saucer, spine, two pods outboard | We add a carrier: four pods, longer spine |
| `hull_raider` | Predator grammar: narrow head, swept wings, tip pods, mass aft | Nothing, it is the right shape |
| Both | Under 600 triangles, silhouette first | Detail is wanted: add texture maps, not geometry |

Two ships we do not have and should, in this vocabulary: a **carrier** (four pods,
long spine, bay recesses along it) and a **frigate** (short spine, two pods, no
secondary hull) so the Kestrel and the Talon stop borrowing hulls from their
bigger siblings.
