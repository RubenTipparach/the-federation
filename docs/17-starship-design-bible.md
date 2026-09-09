# 17. Starship design bible

How the starships of the Star Trek tradition are designed, built, painted and lit, taken
from the people who did it, and what our hulls take from that. It extends
[12](12-ship-design-language.md), which recorded the silhouette grammar from the Starfleet
Command era models; this document goes further back, to the studio floor, and covers the
things a silhouette does not: production practice, kitbashing, surface detail, liveries,
lighting, the parts a ship is assembled from, and the dialects each culture speaks.

Two rules frame everything here, both from CLAUDE.md section 10.

- **Take the shape, not the text.** The ships named below are named as study subjects, the
  way a life class names the model. None of their names, registries, emblems, fonts or
  artwork belong in this repository, and no hull of ours is a copy of one of theirs. What is
  taken is the grammar: why a nacelle is where it is, what a window row says, why a hull is
  smooth.
- **The paint stays pixel art.** This was decided again on 2026-09-07 after a procedural
  surfacing experiment, and it is not up for relitigation here. Every rule about surface,
  light and livery below ends in what it means at one texel on a 128 grid, drawn with
  palette roles under CLAUDE.md 3.1.

The interactive companion to this document is the three.js diorama page,
`docs/mockups/starship-dioramas.html`, built by `tools/gen_dioramas.py` from its template
under `tools/dioramas/` and the palette. It builds
original ships in this grammar from a kit of parts, pixel art textured, and lets each one be
orbited, seen from directly above, and checked at 60 pixels. Section 12 says what it shows.

---

## 1. Where this comes from

Everything below rests on named sources, listed in section 13. The load bearing ones:

- **Matt Jefferies**, who designed the first of these ships and whose reasoning is the
  root of the whole tradition: powerful engines held away from the hull, a smooth hull
  with the machinery inside, and a registry number chosen because it "could be spotted
  quickly".
- **Gene Roddenberry's four rules**, as recorded and explained by Rick Sternbach and
  Michael Okuda in the *Next Generation Technical Manual* and analysed by Bernd Schneider
  at Ex Astris Scientia.
- **Andrew Probert**, on organic curves, forward lean, the bridge as a scale cue, and the
  bird motif of the hostile ships.
- **Doug Drexler**, on building an earlier era into a hull, and on the DS9 kitbash fleet.
- **Michael Okuda**, on the Wolf 359 kitbashes: what was built in a hurry, out of what, and
  why.
- **Paul Olsen and Douglas Trumbull**, on the refit's pearlescent aztec and the idea that a
  ship lights itself.
- Ex Astris Scientia's articles on navigation lights, ship sizes and the kitbashes, and
  99% Invisible on why greebles make things look big.

---

## 2. The grammar in one page

Docs/12 already states it: three kinds of volume, recombined; empire read from proportion
and angle; class read from part count; the top down read as the whole constraint; detail
as texture, not geometry; light saying which way the ship points. This document does not
restate those. It adds the reasons underneath them, and the four rules the tradition wrote
down for itself.

**Roddenberry's four rules**, as the Technical Manual explains them:

| Rule | Reason given | What it does for a viewer |
|---|---|---|
| Warp nacelles come in pairs | "A pair of nacelles is employed to create two balanced, interacting fields" | The ship reads as bilaterally symmetric, like an animal |
| Each nacelle has at least half line of sight to the other across the hull | The two fields interact port to starboard | The nacelles are held outboard, so the top down silhouette has width |
| Both nacelles are fully visible from the front | The collectors at their bows gather hydrogen "predominantly from space directly ahead" | The bow of the ship is a clear line of three noses |
| The bridge is at the top centre of the primary hull | Interchangeable bridge modules across sister ships | A small bump on a big disc, which is what gives the disc its scale |

The manual adds a fifth in passing: nacelles sit symmetrically about the dorsal ventral
centreline, and an odd number of them is a violation. Ships that broke the rules are
recorded as such: a single nacelle here, a hull sitting between the nacelles there, a
collector hidden behind a saucer on an upgraded design.

**Why a game about a top down camera should care.** Every one of these rules pushes mass
outboard and forward, and puts a legible bump on the centreline. Those are precisely the
things a downward camera can see. A rule written for warp field theatre turns out to be a
rule for silhouettes, which is why our hulls obey it without ever mentioning warp.

**Jefferies' two rules underneath the four.** He put the engines away from the body because
they were "extremely powerful" and dangerous, and he kept the hull smooth because "space
presented dangers" and engineers would not hang important machinery outside. He "constantly
had to fight anyone who wanted to put surface details on the thing." The tradition's
detail lives on the inside of the silhouette, as texture, and that is where ours lives too.

---

## 3. The kit of parts

A ship in this tradition is a recombination of a small kit. What follows is each part,
what it says, where the tradition puts it, and how it is drawn at one texel.

### 3.1 Primary hull

The disc, wedge or delta that carries the command volume. Jefferies started from a sphere,
"the best pressure vessel", and flattened it into a saucer when the bulk was impractical.
Probert kept it as "the main section" and made everything else a "compressed oval" of it.
The manual describes the shape progressing circular to elliptical to triangular as the
theory matured.

- **Placement.** Forward and dominant. On the Federation grammar it is the widest single
  element and often half the ship's length. On the predator grammar it narrows to a head.
- **What it says.** Which culture built the ship, before anything else.
- **Bridge.** A small dome or block at top centre, per rule four. Its smallness is the point:
  it is the one human scaled thing on the disc.
- **Rim.** A band of windows in one or two rows, the deck edge. On the underside, a
  sensor dome at centre and the yacht or lifeboats.
- **Top.** Registry and name, the largest marks on the ship, readable from above, plus a
  weapon strip or two curving with the rim on later eras.
- **Trailing edge.** Where the impulse engines sit on a Federation hull, glowing warm.

**At one texel.** The saucer carries the detail budget. Concentric ring seams every eight to
twelve texels, a bridge octagon at centre, registry as a 3x5 digit run, window dots in a
single ring near the rim, one or two red or gold marks off centre so the disc has a
handedness. The R1 sheets in `tools/shiplib.py` already speak this: plates as top lit
ridges with a shadow step, rivets along seams.

### 3.2 Neck and secondary hull

The spine or engineering body behind and below the primary hull. St Minutiae describes the
original as "a simple cylinder", and gives the reason it is behind: the aft body generates
the trailing warp field, and the neck between the two should hold the centre of mass so the
fore and aft fields are centred. Later designs pushed length to height ratios from 1.5 to
1 up past 5 to 1, because "the disparity between the fore and aft warp fields needs to be
significant".

- **Placement.** Behind and below the disc, joined by a neck. Its bow carries the deflector,
  its stern the main shuttle bay on many classes.
- **What it says.** How much ship there is. A frigate omits it; a cruiser has a distinct
  one; a capital doubles it or stretches it.
- **Deflector.** A dish or recessed glow at the bow of the secondary hull, blue with an
  amber core in the movie era, blue in the later one. It is the one forward facing light
  and it is cool, which is half of docs/12's rule that the bow is cool and the stern warm.

**At one texel.** Machinery vocabulary: mid grey blocks with a lit top ridge, a darker
shadow, black rivet dots along the borders, one or two lit dashes for the deflector. The
side texture carries the pennant stripe and a registry in smaller digits.

### 3.3 Pylons

The struts that hold the nacelles out. Jefferies wanted them because the engines had to be
away from the body. Drexler, building an earlier era, used aircraft engine pontoons as the
reference "because it made sense structurally for engine placement without proximity to
the primary hull". Probert slanted every strut forward "like a lunging cat" so the ship
reads as moving.

- **Placement.** From the secondary hull, or from the disc's trailing edge on a frigate,
  out and up or out and down to the nacelles. Swept, never square.
- **What it says.** Direction and intent. Forward rake is aggression; upward is the
  Federation platform; downward with the wings is the predator.
- **Kitbash warning.** The DS9 fleet's failure mode was flimsy pylons that "undermined
  structural credibility". A pylon has to look able to hold the mass at its end.

**At one texel.** Thin, so almost no texture: a single seam line along the length and a
rivet at each root.

### 3.4 Nacelles

The paired warp engines. Every rule in section 2 is about these.

- **Placement.** Outboard, paired, symmetric, with line of sight to each other, and with
  their bows visible from the front. Length and outboard reach say power and size; four in
  two stacked pairs says capital faster than any amount of hull.
- **The bow: the collector.** A warm dome, red or orange, facing forward. On the original it
  spun; on the movie refit it was a glowing cowl; on later hulls it was partly shrouded.
- **The flank: the field grille.** A long cool strip, blue, on the inner face of each
  nacelle, facing its twin. This is why they must see each other.
- **The stern: the aft cap.** A vent or a light, often where a navigation light sits.

**Temperature.** Warm at the front, cool along the side. Combined with the impulse engines
at the disc's trailing edge, the ship reads as warm at the stern and cool at the bow from
a distance, which is the navigational job docs/12 section 6 gives to light. The Kthaari
hull inverts it deliberately, warm hull and cool drives, so the two fleets read as
opposites before any marking.

**At one texel.** The nacelle top is a long plate with a seam down the middle and a few
dashes; the inner side is a dithered grille strip over a six step ramp, which is the R6
sheets' checker dither; the bow is a warm ramp; the aft face a grille square. These are
the largest emissive areas on the ship and they carry the aft read at tactical scale.

### 3.5 Impulse engines

The sublight drive, on the trailing edge of the primary hull or the secondary hull's stern.
The convention is a clear path behind them and a height of one or two decks. They glow warm,
red to orange.

**At one texel.** A block one to two texels tall at the disc's trailing edge, lit with the
glow ramp, in the lights map.

### 3.6 Shuttle bays

Aft facing, almost without exception, because a bay that opens forward is a bay into the
ship's own motion. The original carried one at the stern of the secondary hull behind
clamshell doors; the later era put a main bay in the disc's trailing edge and two more
aft on the secondary hull. Bay doors are large flat rectangles, which makes them one of
the better scale cues on a hull.

**At one texel.** A pale rectangle two to three texels tall on the stern face, outlined,
with one lit dash for the landing strip. It is a mark on the stern texture, not geometry.

### 3.7 Scale cues

Windows, lifeboats, bay doors, the bridge. Ex Astris Scientia's rule of thumb is a deck
every 3.5 metres and window rows following decks, so the count of rows says how big the
ship is. Probert made the bridge return to the saucer top not for function but because "it
gave the viewers a sense of scale". 99% Invisible states the general principle: "we use
details as cues to estimate size, particularly against backdrops that are absent reference
points", and the detail that does this on a hull is the human sized kind.

**At one texel.** One window is one texel. One deck row is one ring of dots. A frigate has
one row, a cruiser two, a capital three. Nothing else on the ship is allowed to be one
texel tall, so a one texel mark is always a window and always says "a person could stand
there". That is the whole trick, and it costs nothing.

### 3.8 Weapons and sensors

Weapon strips curve with the disc rim on later hulls; on earlier ones weapons are small
turrets or emitters at the rim and on the secondary hull. Torpedo launchers sit at the
root of the neck, facing forward. Sensor domes sit at the disc's centre top and bottom.

**At one texel.** Weapons are not painted, because our mounts are data and their arcs are
drawn by the sim. A launcher is a small dark rectangle at the neck; a dome is a two
texel circle at the disc centre.

---

## 4. Light

### 4.1 The three eras of hull lighting

- **The original.** A model floodlit on a stage, with the windows as lit points and the
  collectors spinning. The hull was smooth and reflective; that was its texture.
- **The movie refit.** Trumbull "had the internal lighting rewired to satisfy his vision of a
  concept of self-illumination as opposed to a model completely awash in light". The ship
  carried its own floodlights, aimed at its registry and pennants, and was shot against
  black velvet on a low lit stage. This is the origin of the lit registry: a starship is
  its own lamp.
- **The later era.** Windows as scale, in rows, with public spaces drawn larger.

**For us.** Our tactical camera is the floodlit stage, so the emissive map is the second and
third eras: windows in rows, lit registry, drives. The R6 parity law in `gen_ship_raider.py`
is the modern version of Trumbull's rule: every lit pixel is emissive, and the lights map
repeats the diffuse pixel exactly, so a mark is lit or it is not.

### 4.2 Navigation lights

Maritime and aviation convention: red to port, green to starboard. Ex Astris Scientia's
survey of the tradition:

- On the original, red and green on the saucer's top edges only, flashing about every two
  seconds.
- From the movies on, on both dorsal and ventral saucer edges.
- On the later hulls, saucer edges plus aft positions, behind the shuttle bay, and on the
  nacelle aft ends; runabouts put them on the nacelles; one small warship put them on the
  pennant edges of its engine cowlings.
- Unlike real ships, they are visible from every angle.
- The one series that put green on both sides is recorded as an error.

**For us.** Red port, green starboard, at the saucer rim's widest points, on the nacelle
aft caps, and behind the bay. A slow two second blink. In the tactical view they are
subordinate to the shield facings and the arc overlays, so they are one texel in the lights
map and one tinted point sprite in the rig, never a light source. The plan view inset gets
them too: they are the cheapest heading cue in the game after the bow itself.

### 4.3 The colour code of glow

| Light | Colour | Where | Says |
|---|---|---|---|
| Collectors | Warm, red to orange | Nacelle bows | The engines are at the back, and which back |
| Field grilles | Cool, blue | Nacelle inner flanks | The nacelles are a pair |
| Impulse | Warm, red to orange | Disc trailing edge | Stern |
| Deflector | Cool, blue with an amber core | Secondary hull bow | Bow |
| Windows | Warm white to gold | Deck rows | Scale, and that the ship is crewed |
| Navigation | Red port, green starboard, white strobe | Extremities | Heading and width |

Our palette roles: `glow_core`, `glow_light`, `glow_mid`, `glow_halo` for the warm ramp,
`window` and `glow_window` for the decks, the six step `grille_ramp` for the cool strips,
`plume_*` for the Kthaari cool drives. Nothing here needs a new colour.

---

## 5. Liveries and markings

### 5.1 The registry

Jefferies picked a number that "could be spotted quickly" and later explained it as the
seventeenth design, first of its class. Two lessons: a registry is short and high contrast,
and it encodes something. Starfleet ships "often wrote their registry numbers on their outer
hulls, and even illuminated these numbers with spotlights".

- **Placement.** Largest on the disc top, readable from above and from the bridge of another
  ship; repeated on the disc underside; smaller on the secondary hull flanks and along the
  nacelle tops.
- **Ours.** A hull carries a yard number and a class mark, never a Starfleet prefix and
  never their font. The digits are a 3x5 pixel face in the `mark` or `accent` role, and
  they sit exactly where the tradition puts them.

### 5.2 Pennants and stripes

A stripe along the secondary hull and along the nacelle flanks, carrying the fleet emblem
and the name, red and blue on the movie hulls, grey and blue later. Navigation lights sit at
the ends of the nacelle pennants on some hulls. The stripe is the one place a livery uses
a saturated colour on an otherwise grey hull, which is why it reads.

**Ours.** One stripe per faction, in the faction's `accent` role, running the length of the
spine and the pod tops. It is the second most readable mark after the registry and it is
what a captured hull keeps, so a prize reads as taken rather than repainted.

### 5.3 Hull colour

The Federation hull is a pale grey, cool, close to "light gray (RAL 7035)" in the modelling
guides, with the pearlescent aztec of the refit shifting it blue, gold, red and green under
oblique light. Hostile hulls are dark: Klingon green grey, Romulan green, Cardassian ochre.

**Ours.** The palette decides: the Federation hull is `indigo` under `blue_light` plates, the
Kthaari `clay_deep` under `bronze` and `gold_deep`. Faction identity is hull colour first,
stripe second, silhouette always.

### 5.4 The livery table

| Faction | Hull | Plates | Stripe | Glow | Silhouette |
|---|---|---|---|---|---|
| Terran Concord | cool indigo | steel blue | pale blue grey | warm aft, cool bow | disc, spine, pods |
| Kthaari Dominion | rust | bronze, gold | moss green | cool drives, warm hull | head, neck, wings, tip pods |
| Vaelith Ascendancy | dark green | verdigris | none, feathers instead | cool green, a single warm eye | beak, hollow loop, wide flat wings |
| Sarn Concordance | ochre | amber facets | copper | amber, many small bays | faceted body, forward rake, a ring |
| Helion Combine | gunmetal | olive, drab | hazard gold and black | warm windows on the command block, cool drives | truss spine, clamped modules, engine cluster |
| The Bloom | plum black | none | none | bioluminescent, irregular | no axis of symmetry |

The Vaelith and Sarn rows are proposals: neither has a hull yet, and their palette roles do
not exist. They are written here so the first hull for each starts from a decision rather
than from a blank atlas.

---

## 6. Surface

### 6.1 Smooth, then gridlines, then aztec

The original model was smooth with pencilled gridlines, because the designer fought detail.
The refit gained the aztec: Paul Olsen spent eight months airbrushing a pattern of
interlocking panels in "four pearl colors that were transparent: a blue, a gold, a red, and
a green, that all flip-flopped to their complements when the viewing angle changed", visible
only when light hit at an oblique angle. The later hulls kept the aztec as painted panels in
two close greys.

**For us.** The aztec is the plate tone. On a 128 grid at two device pixels per texel, a
plate is a rectangle of the `plate` role with a `plate_light` top ridge and a `plate_shadow`
bottom and right, exactly as `shiplib.R1` draws it, and neighbouring plates alternate between
`plate` and one step off. That is the pearlescent flip flop at the resolution we have. No
plate is ever drawn with a black outline; outlines belong to the silhouette and to
machinery.

### 6.2 Greebles

Small relief parts that "imply mechanical function without necessarily having any real
purpose" and "trick the eye into seeing scale". The Federation hull is the clean end of the
spectrum; the cobbled together end is a freighter or a raider that has been patched for
years. Density is a statement about who owns the ship and how long they have had it.

**For us.** A greeble is a one to three texel mark in the machinery vocabulary: a dash, a
dot, an L. Density is per faction: Terran hulls are sparse and regular; Kthaari hulls carry
more, irregular, in the warm ridge tones; the Bloom, when it exists, is all greeble. The
limit is the 60 pixel test: if the marks turn to noise at 60 pixels, there are too many.

### 6.3 Weathering

Studio ships were mostly clean. Damage was cut with a Dremel and painted after, for the
wrecks. Our wear is not painted at all: it is the shot away boxes, the fires, and the
wreck's own fragments, which are cut from the hull's real triangles and keep its paint. A
hull is pristine until the sim says otherwise.

---

## 7. Kitbashing, and what it teaches

The studios built fleets out of model kits when time and money ran out.

**Wolf 359.** The wrecks were "kit-bash starship classes" built in weeks: two by Greg Jein's
shop from its own assets, the rest by Ed Miarecki out of AMT kits with custom parts,
damaged by Michael Okuda with a Dremel. Okuda used "submarine parts" and "fairly stock"
nacelles; one class had nacelles "made from marker pens"; another used "a scaled-down
Galaxy saucer (meaning it was made from an Enterprise kit)". The purpose was
world building: "I wanted to show that the Enterprise-D was only one of many similar ships
with related designs, even if she was the largest and most powerful."

**The rag tag fleet.** For a war episode that needed many damaged ships at once, the effects
department "collected model kits" and invited everyone to "make a ship and we'll put your
name on it". Saucers from one kit, nacelles from another, pylons rotated or inverted, a
fighter fuselage reversed as a deflector, two saucer tops glued rim to rim.

**What went wrong**, per Ex Astris Scientia's review: "real starship components are not
designed to be cut off somewhere and welded together in a new configuration". Kits came in
incompatible scales, so nacelles were "consistently oversized"; windows landed in places
that implied "illogical deck layouts"; pylons were flimsy.

**What worked.** Simple parts stayed believable at the wrong scale. Fluorescent paint on
windows and grilles, shot under UV in a second pass, gave convincing internal light.
Copper details "distracted from seams and construction imperfections". And the ships were
background, so nobody looked long.

**The lesson, and it is the design principle of this repository's hulls.** Kitbashing fails
when parts come from different scales and succeeds when they come from one. Our slab
vocabulary in `tools/gen_ship_*.py` is a kit at one scale: a disc, a neck, a body, a pylon,
a pod, each with its own atlas rectangle and its own paint. New classes are new
recombinations of those parts, never rescaled parts. The carrier docs/12 asks for is the
cruiser's parts with four pods and a longer spine; the frigate is the cruiser's disc and
pods with no body. The window row rule (section 3.7) is what stops the "illogical deck"
failure: a part's windows are painted per part, so they stay one row per deck wherever the
part ends up.

---

## 8. Dialects

The tradition has one grammar and several dialects. Each is a set of choices about
proportion, angle, colour and texture. Ours map onto them without copying them.

### 8.1 The Federation dialects, by era

| Era | Proportion | Surface | Light | Take away |
|---|---|---|---|---|
| Original | disc half the length, cylinder body, straight pylons up | smooth, pencil grid | floodlit, spinning collectors | The clean baseline |
| Refit | same masses, refined, tapered nacelles | pearl aztec, oblique | self lit, spotlights on the registry | The lit registry, the plate flip flop |
| Late | huge elliptical disc, organic curves, forward lean | two grey aztec, window rows | windows as scale, blue grilles | Forward rake, decks as scale |
| War era | compact, angular, disc buried in the body, heavy plating | armour panels, few windows | dim, weapon glow | The military variant of the grammar |
| Early era | disc with pontoon nacelles, no secondary hull | riveted plates, submarine and aircraft references | sparse | How to make a hull read as older |

### 8.2 The hostile dialects

- **Klingon.** Jefferies' "manta ray": a long neck, a bulbous command head forward, wings
  swept back and down, nacelles on the wings, mass aft, green grey, exposed structure. The
  later bird of prey added pivoting wings and painted feathers. It reads as a predator with
  its head down.
- **Romulan.** Started as a saucer with a painted bird, then took the Klingon hull, then
  Probert reinvented it: "bird and bird wing shapes", a downturned beak, and a hollow loop
  body with "no obstructions between the engines". Green, sleek, wide, and stealthy.
- **Cardassian.** Sternbach's "faceted surface", ochre, forward raked, a flattened teardrop
  with a raised spine. Reads as armour and administration.
- **Vulcan.** A single elongated hull and one strut to an engine hoop, "inspired by 1950s
  hood ornaments", "dedication to harmony". The ring is the whole idea.
- **Borg.** A cube. "Simplistic shape and exposed machinery conveys a sense of uncompromising
  efficiency." The anti design: no bow, no stern, no lights that mean anything.

### 8.3 Our dialects

| Faction | Takes from | Proportion and angle | Surface | Light |
|---|---|---|---|---|
| Terran Concord | Federation, refit and late eras | dominant disc, spine, paired pods above the plane, forward rake | sparse regular plates, one stripe | warm aft, cool bow, lit registry, two window rows |
| Kthaari Dominion | Klingon | narrow armoured head, thin neck, body deepest aft, swept wings, tip pods; the plan changes with class (below) | dense irregular plating, warm ridges, chevrons | cool drives, warm hull, few windows |
| Vaelith Ascendancy | Romulan, plus the Vulcan ring | beak forward, hollow loop, wide flat wings, everything low | smooth, feather bands on the underside | one warm eye at the beak, cool green loop |
| Sarn Concordance | Cardassian, plus the Vulcan ring | faceted body, forward rake, a ring or hoop for the tractor web, bay mouths in rows | amber facets, copper seams | amber, many small bay lights |
| Helion Combine | the working ships of section 7, freighters and tugs rather than any navy | a truss spine, a command block forward, standard modules clamped on above and below, an engine cluster on outriggers aft | hazard stripes, exposed frames, containers in three tones | warm windows on the command block, cool drives, nothing decorative |
| The Bloom | Borg and the organic ships | no symmetry axis, growth, lobes | nodules, no plates | bioluminescent, irregular, never red or green |

**The Kthaari plan changes with class.** A fleet where every hull is the same bird at a
different size reads as one ship, so the grammar stays and the shapes move. The head is
narrow, a hammer, a bulb or a beak; the body is a box, an oval, a wedge or a slab; the wing
plan is swept, forward swept, straight, cranked, gull or delta; capital ships carry two
pairs, stacked or crossed. The roster page keys each class to one combination, and a new
hull picks its own rather than reusing a neighbour's.

**The Vaelith and Sarn plans change with class the same way.** A Vaelith loop is round,
oval, a horseshoe open aft, an egg fuller at the stern, or concentric, and never two loops side by side; the head is a
beak, a spade or a lance; the capital ships add flat wings past the loop. A Sarn body is a
cut diamond, a many faceted hull, a long spindle, a wide flat diamond, a twenty sided gem
or two stacked; the ring sits aft, round the waist as a belt, over the stern as an arch,
or twice; the prow is a cone, a blade or a trident. The hole and the circle survive every
combination, which is the point: the gesture is the faction, the plan is the class.

The three unbuilt dialects each get one gesture no other faction has: the Vaelith hollow
loop, which is a silhouette with a hole in it; the Sarn ring, which is a silhouette with a
circle in it; and the Helion truss, which is a line with boxes clamped to it, so that class
reads as a count of boxes. From directly above at 60 pixels, a hole, a circle and a line
of boxes are three things that cannot be confused with a disc, a wedge or a bird.

The Helion Combine is the GDD's sixth faction, the modular mercantile one, and it is not in
the sections above because its ancestors are not a navy. Its dialect is the kitbash lesson
of section 7 made deliberate: repeated standard parts, visible fixings, and a silhouette
that says what the ship carries. Cheapest hulls, most mount flexibility, so the modules
ARE the mounts, and a refit is a different set of boxes on the same truss.

---

## 9. Class is part count

Docs/12 section 3 states it. This is the table.

The ladder is the one docs/02 section 2 names: seven fighting classes and three variants.

| Class | Disc | Neck | Body | Pods | Spine | Window rows | Pixels across at tactical zoom |
|---|---|---|---|---|---|---|---|
| Frigate | small | none | none | 2 | short | 1 | 40 |
| Destroyer | medium | short | short | 2 | medium | 1 | 50 |
| Light cruiser | large | yes | yes | 2 | full | 2 | 60 |
| Heavy cruiser | large | yes | long | 2, long | full | 2 | 70 |
| Battlecruiser | large | yes | long | 2, long, low | full | 2 | 80 |
| Battleship | large | yes | doubled | 4, stacked pairs | full | 3 | 90 |
| Dreadnought | large | yes | doubled | 4, long | long | 3 | 100 |
| Carrier | large | yes | bay lined | 4, stacked pairs | long | 3 | 90 |
| Freighter | small | none | a spine of cargo | 2 | long | 1 | 70 |
| Tender | small | short | a short cargo run, cranes forward | 2 | medium | 1 | 60 |

Size scales the draw, so the last column is only a rough read. The rule is the pods and the
body: two pods and no body is small, two and a body is a cruiser, four is capital, the body
doubling is a battleship, and the body lining with bays is a carrier. The variants have
tells of their own: cargo is the silhouette of a freighter, and the cranes are the
tender's, because nothing else in a fleet reaches forward.

Every faction spends the same row in its own dialect. A Kthaari battleship doubles its
body with a dorsal hull and puts the second pod pair under the wings; a Vaelith one raises
a second loop inside the first; a Sarn one stacks a second faceted body above the first;
a Helion one clamps a module both above and below the truss at every station; and a Bloom
one simply buds more lobes, because it never had parts to count.

---

## 10. The pixel art rules

The paint is pixel art and stays so. The rules below are the ones the painters already
follow, gathered so a new hull can be painted without reading three generators.

- **Grid.** Authored at 128, exported at 2x nearest. One texel is a fat chunk on screen.
- **Palette.** Every texel is a role in `data/palette.json` `ships`, resolved by name, and
  `tools/shiplib.py` `verify()` refuses anything else before a file is written.
- **Vocabularies.** R1 for the Terran hulls: plates as top lit ridges with a shadow step,
  no black outlines on plates, machinery in mid grey with a lit ridge and black rivets. R6
  for the Kthaari: a dark hull with one texel outlines, panel work one step lighter, massed
  armour with ridge lines, checker dithered grilles, tapering jittered plumes.
- **Atlas.** One rectangle per part, non overlapping, and every painted texel inside one.
  The mesh and the atlas are one decision written by one painter.
- **Emissive.** The lights map is a subset of the diffuse: every lit texel repeats its
  diffuse colour exactly (the R6 parity law). The engines map is a subset of the lights.
- **Scale.** One texel is a window and nothing else is one texel. One row per deck.
- **Greebles.** One to three texel marks in the machinery vocabulary, density per faction,
  bounded by the 60 pixel test.
- **Glow.** Six step ramps, checker dithered, never a gradient. Warm at the stern, cool at
  the bow, inverted for the Kthaari.
- **Marks.** Registry as 3x5 digits in the `mark` role, stripe in `accent`, one or two
  handedness marks in `red` or `gold` off centre on the disc.

---

## 11. What a better hull is, given all of this

The geometry is where the next improvement lives, not the paint. From the tradition:

1. **Taper.** Nacelles taper to the stern and carry a distinct bow cap and aft cap. The
   secondary hull tapers to the stern. Ours are prisms.
2. **Rake.** Pylons lean forward. Ours are square to the body.
3. **Rim profile.** A saucer has a rim, a step, and a shallow dome. Ours is a flat disc.
4. **The neck.** A real neck is a blade, thin from the side and tall. Ours is a box.
5. **Height.** Nacelles sit above the disc's plane on the Federation grammar and below the
   wings on the predator. Ours are level.
6. **Part count for class.** The carrier and the dreadnought do not exist yet, and the
   frigate should lose its secondary hull.

Each of these is a change to `build_mesh()` in the generator that owns the hull, repainted
through the same atlas layout, with the fragments and wireframes regenerated by the tools
that already read the committed `.obj`. None of them touches the paint pipeline, and none
adds triangles that the 60 pixel test can see.

---

## 12. The diorama page

The companion page builds the whole roster, six factions by the ten classes of section 9,
sixty original hulls from one parametric kit, in three.js, textured with canvas painted
pixel art in the project palette at nearest filtering. Every face is projected flat along
its own axis at one texel density, so a plate is the same size on a pod, a wing and a
hull, and a taper foreshortens by a few percent instead of stretching.

Detail is two layers over the plates, both shared by every faction. The painted layer is
section 6 at one to five texels: aztec sub plates in a third tone, panel lines with a lit
rivet, lifeboat rows, hatches, thruster quads, phaser strips, sensor domes, docking ports,
scorch streaks and hull ticks. The mounted layer is one kit of small meshes, domes, drums,
hoops, fins, spikes, cannons, cranes, containers and blocks, parented to the part they sit
on so an exploded view carries them. A button hides the mounted layer so a silhouette can
be judged on its own.

Each hull can be orbited, snapped to the top down view the game uses, and rendered at 60
pixels beside the full view, which is the only test that matters. A roster sheet renders
all sixty top down at one scale, ten pixels to a unit, so the class ladder can be read
across a row and the dialects down a column. Navigation lights blink red to port and green
to starboard; collectors, grilles, impulse and deflector glow in the colour code of
section 4.3; a kitbash panel changes pod count, pylon rake, disc size and spine length
live so the part count rule can be felt rather than read. The parts can be exploded to
show the kit.

**Windows are decals, and there is one kind per faction.** The page pastes windows
onto the hull surface rather than painting them into the plate texture, the way Fallen
Tribes does it: a small quad per window, batched into one mesh per part, cut from a strip
of six variants whose panes are lit, dim or dark, with the variant picked per window by a
hash so a run down a flank reads as a ship with people in it rather than a repeated panel.
The glass is dark in the colour map and only the emissive map carries the light, so a lit
pane is its palette colour and never white. Every kind is built from one texel panes,
because one texel is a window (section 10): the Terran pair, the Kthaari slit of three, the
Vaelith upright oval, the Sarn two by two hex, the Helion single porthole and the Bloom
pore. The size never changes with class. That is the point: a window is the scale bar,
and a dreadnought has more rows of the same pane, never a bigger pane.

It is a review artifact. The ships in it are not assets; the assets are the committed
`.obj` and `.png` files that `tools/gen_ship_*.py` writes, and the page exists so the next
version of those can be agreed before it is generated.

---

## 13. Sources

- Ex Astris Scientia, Starship Design Guidelines:
  https://www.ex-astris-scientia.org/articles/design.htm
- Ex Astris Scientia, Navigation Lights on Starfleet Ships:
  https://www.ex-astris-scientia.org/articles/navigation-lights.htm
- Ex Astris Scientia, The DS9TM Kitbashes:
  https://www.ex-astris-scientia.org/articles/ds9tm.htm
- Ex Astris Scientia, Wolf 359, Interview with Michael Okuda:
  https://www.ex-astris-scientia.org/articles/okuda359.htm
- Ex Astris Scientia, Starship Sizes:
  https://www.ex-astris-scientia.org/articles/ship_sizes.htm
- Ex Astris Scientia, Ten Favorite Alien Ship Designs:
  https://www.ex-astris-scientia.org/rankings/ten-best-alienships.htm
- Ex Astris Scientia, Starship Modeling Guidelines:
  https://www.ex-astris-scientia.org/reviews/modeling.htm
- Forgotten Trek, Designing the First Enterprise:
  https://forgottentrek.com/the-original-series/designing-the-first-enterprise/
- Forgotten Trek, Designing the Next Generation Enterprise:
  https://forgottentrek.com/the-next-generation/designing-the-next-generation-enterprise/
- Forgotten Trek, Designing the Romulan Warbird:
  https://forgottentrek.com/the-next-generation/designing-the-romulan-warbird/
- Collecting Trek, Doug Drexler on designing the NX-01:
  https://collectingtrek.ca/2024/07/31/drexler-nx-01/
- St Minutiae, Basic Starship Design:
  https://www.st-minutiae.com/articles/shipdesign/index.html
- 99% Invisible, Greebles Lend Large Sci-Fi Structures a Sense of Scale:
  https://99percentinvisible.org/article/interstellar-illusions-greebles-lend-large-sci-fi-structures-a-sense-of-scale/
- Screen Rant, Why Klingons and Romulans Both Have Bird of Prey Starships:
  https://screenrant.com/star-trek-klingons-romulans-bird-of-prey-explainer/
- BGR, The Four Gene Roddenberry Rules That Guided Star Trek's Starship Designs:
  https://www.bgr.com/2203622/star-trek-creator-gene-roddenberry-starship-designs-rules/
- Hobby Talk threads on painting the refit, for Paul Olsen's pearl technique as reported
  by modellers: https://www.hobbytalk.com/threads/painting-the-refit-st-tmp.188494/
- Trek BBS, Douglas Trumbull and the self illuminated refit:
  https://www.trekbbs.com/threads/video-douglas-trumbull-saved-star-trek-the-motion-picture.321228/

The *Star Trek: The Next Generation Technical Manual* (Sternbach and Okuda, 1991) is the
primary source for the four rules; it is quoted here only through the Ex Astris Scientia
analysis, and nothing from it is reproduced.
